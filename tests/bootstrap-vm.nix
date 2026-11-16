# A test function, bound in nix/shared.nix and applied in nix/checks.nix
# (and nix/falsifiers.nix) once per variant.
# Two 0.6 edgenodes and a holochain-bootstrap server on a network with
# no way out: the only place alice and bob can learn about each other,
# and the only relay they can get a peer URL from, is `bootstrap`.
# The pass condition is that each conductor holds the other's agent
# info for Kando's DNA, with a peer URL on that relay.
#
# `bobBootstrapPort` exists for the falsifier: pointed at a port
# nothing listens on, bob never registers and the same assertion has
# to fail (legacyPackages.falsifiers). Relay and bootstrap are both
# plain HTTP, which is what relayAllowPlainText is for.
{
  adminCall,
  edgenodeNode,
  hcOnPath,
  kandoHapp,
  on06,
  pkgs,
  self,
  ...
}: {
  name,
  bobBootstrapPort ? 443,
}:
pkgs.testers.nixosTest {
  inherit name;
  nodes = let
    edgenode = port: {
      imports = [edgenodeNode hcOnPath on06];
      virtualisation = {
        cores = 2;
        memorySize = 2048;
        diskSize = 4096;
      };
      services.holochain-edgenode = {
        enable = true;
        bootstrapUrl = "http://bootstrap:${toString port}";
        relayUrl = "http://bootstrap:443/relay";
        relayAllowPlainText = true;
        # The conductor default, set so the rendered key is proven
        # accepted by a real 0.6 conductor without changing behaviour.
        requestTimeoutS = 60;
        happs.kando = {
          src = kandoHapp;
          networkSeed = "ci-bootstrap-seed";
        };
      };
    };
  in {
    bootstrap = {
      imports = [self.nixosModules.holochain-bootstrap];
      services.holochain-bootstrap = {
        enable = true;
        openFirewall = true;
      };
      environment.systemPackages = [pkgs.procps];
    };
    alice = edgenode 443;
    bob = edgenode bobBootstrapPort;
  };
  testScript = ''
    import json
    import re
    import time

    CALL = "${adminCall."0.6"}"


    def cpu_ns():
        return int(bootstrap.succeed(
            "systemctl show -p CPUUsageNSec --value holochain-bootstrap.service"
        ))


    def report(label, cpu0, t0):
        """The server's RSS now, and its CPU since (cpu0, t0), from the unit's accounting."""
        cpu1, t1 = cpu_ns(), time.monotonic()
        pid = bootstrap.succeed(
            "systemctl show -p MainPID --value holochain-bootstrap.service"
        ).strip()
        rss_kb = int(bootstrap.succeed(f"ps -o rss= -p {pid}").strip())
        threads = bootstrap.succeed(f"ps -o nlwp= -p {pid}").strip()
        peak = bootstrap.succeed(
            "systemctl show -p MemoryPeak --value holochain-bootstrap.service"
        ).strip()
        cpu_pct = (cpu1 - cpu0) / ((t1 - t0) * 1e9) * 100
        bootstrap.log(
            f"MEASURE {label}: rss={rss_kb} KiB ({rss_kb / 1024:.1f} MiB)"
            f" cgroup_memory_peak={peak} B"
            f" cpu={cpu_pct:.3f}% of one core over {t1 - t0:.0f}s"
            f" cpu_time={(cpu1 - cpu0) / 1e6:.0f} ms threads={threads}"
        )


    def window(label, seconds):
        cpu0, t0 = cpu_ns(), time.monotonic()
        time.sleep(seconds)
        report(label, cpu0, t0)


    def app_facts(node):
        apps = json.loads(node.succeed(f"{CALL} list-apps"))
        app = next(a for a in apps if a["installed_app_id"] == "kando")
        dna = sorted(set(re.findall(r"uhC0k[A-Za-z0-9_-]+", json.dumps(app))))
        assert len(dna) == 1, f"expected one DNA hash, got {dna}"
        return app["agent_pub_key"], dna[0]


    def agent_infos(node, dna):
        """Every agent info the conductor holds for the DNA.

        hc 0.6.3 answers with one object per agent, carrying the
        peer `url`, which for an iroh peer is
        `<relay>/<endpoint id>` and so unique to one conductor. It
        fills `agent_pub_key` only for the conductor's own cells and
        leaves it null for a remote agent, so a remote agent is
        recognised by its URL, not its key.
        """
        out = node.succeed(f"{CALL} list-agents --dna {dna}")
        node.log(f"list-agents on {node.name}: {out}")
        return json.loads(out)


    # ---- the server, alone ----
    bootstrap.start()
    bootstrap.wait_for_unit("holochain-bootstrap.service")
    bootstrap.wait_for_open_port(443)
    bootstrap.succeed("curl -sf http://127.0.0.1:443/health")
    user = bootstrap.succeed(
        "ps -o user= -p $(systemctl show -p MainPID --value holochain-bootstrap.service)"
    ).strip()
    assert user != "root", "the server runs as root"
    bootstrap.log(f"server runs as dynamic user {user}")
    window("idle, no conductors", 30)

    # ---- two edgenodes on the same seed ----
    exchange_cpu, exchange_t = cpu_ns(), time.monotonic()
    alice.start()
    bob.start()
    for node in [alice, bob]:
        node.wait_for_unit("holochain-conductor.service")
        node.wait_for_unit("holochain-happ-installer.service")
        # The server answers over the vlan, not only on loopback.
        node.succeed("curl -sf http://bootstrap:443/health")
        # The config path is on the running conductor's command line.
        path = node.succeed(
            "tr '\\0' ' ' < /proc/$(systemctl show -p MainPID --value"
            " holochain-conductor.service)/cmdline"
            " | grep -o '/nix/store/[^ ]*conductor-config.yaml'"
        ).strip()
        config = node.succeed(f"cat {path}")
        assert '"relayAllowPlainText":true' in config, config
        assert "request_timeout_s: 60" in config, config

    alice_id, dna = app_facts(alice)
    bob_id, bob_dna = app_facts(bob)
    assert dna == bob_dna, f"different DNAs: {dna} vs {bob_dna}"
    assert alice_id != bob_id
    alice.log(f"dna={dna} alice={alice_id} bob={bob_id}")


    # iroh writes the relay host as a fully qualified name, with a
    # trailing dot: http://bootstrap.:443/relay/<endpoint id>.
    ON_OUR_RELAY = re.compile(r"^http://bootstrap\.?:443/relay/")


    def own_url(node, key):
        """The peer URL a conductor published for its own agent, if any yet."""
        for info in agent_infos(node, dna):
            if info["agent_pub_key"] == key:
                return info.get("url")
        return None


    def sees(node, other, other_key):
        url = own_url(other, other_key)
        if url is None or ON_OUR_RELAY.match(url) is None:
            return False
        holds_info = any(
            info.get("url") == url and info["agent_pub_key"] is None
            for info in agent_infos(node, dna)
        )
        # And a live connection to that conductor's endpoint, the
        # last path segment of its URL.
        stats = json.loads(node.succeed(f"{CALL} dump-network-stats"))
        endpoint = url.rstrip("/").rsplit("/", 1)[-1]
        connected = any(
            c.get("pub_key") == endpoint
            for c in stats["transport_stats"]["connections"]
        )
        return holds_info and connected


    start = time.monotonic()
    try:
        with alice.nested("each conductor holds the other's agent info"):
            retry(lambda _: sees(alice, bob, bob_id) and sees(bob, alice, alice_id), timeout_seconds=300)
    finally:
        alice.succeed(f"{CALL} dump-network-stats >&2")
        bob.succeed(f"{CALL} dump-network-stats >&2")
    alice.log(f"MEASURE discovery: both sides saw each other after {time.monotonic() - start:.0f}s")
    report("boot to mutual discovery of two conductors", exchange_cpu, exchange_t)
    window("two conductors connected, steady state", 60)
  '';
}
