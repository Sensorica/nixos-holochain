# Moved verbatim from flake.nix (AD1); called from nix/checks.nix with the
# shared per-system arguments of nix/shared.nix.
# A real zome call through the gateway, on a node that installed a
# real hApp. The allow list names exactly one read function, so the
# 200 proves the whole path (conductor -> admin API -> app websocket
# -> zome -> JSON) and the 403 proves the allow list is what decides,
# not the absence of a route: `get_all_dinos` exists, takes the same
# (empty) payload and lives in the same zome as the allowed
# `get_all_dinos_local`.
{
  dinoAdventureHapp,
  edgenodeNode,
  hcOnPath,
  pkgs,
  roomToWork,
  self,
  ...
}:
pkgs.testers.nixosTest {
  name = "holochain-http-gateway";
  nodes.machine = {
    imports = [
      edgenodeNode
      hcOnPath
      roomToWork
      self.nixosModules.holochain-http-gateway
    ];
    environment.systemPackages = [pkgs.jq];

    services.holochain-edgenode = {
      enable = true;
      appPort = 8888;
      happs.dino-adventure = {
        src = dinoAdventureHapp;
        networkSeed = "ci-gateway-seed";
      };
    };

    services.holochain-http-gateway = {
      enable = true;
      allowedAppIds = ["dino-adventure"];
      allowedFns.dino-adventure = ["dino_adventure/get_all_dinos_local"];
    };
  };
  testScript = ''
    import re

    machine.wait_for_unit("holochain-conductor.service")
    machine.wait_for_unit("holochain-happ-installer.service")
    machine.wait_for_unit("holochain-http-gateway.service")
    machine.wait_for_open_port(8090)

    state = machine.succeed(
        "systemctl is-active holochain-http-gateway.service"
    ).strip()
    assert state == "active", f"expected active, got {state}"

    # /health is the only path that works with nothing allowed, so it
    # separates "the gateway is up" from "the call was authorised".
    health = machine.succeed("curl -sf http://127.0.0.1:8090/health").strip()
    machine.log("health: " + health)

    # The gateway addresses a cell by DNA hash, which is only known
    # once the app is installed. Every holo_hash is multibase 'u' plus
    # a three-byte type prefix, and DnaHash's is hC0k, so this picks
    # the DNA hash out of list-apps without depending on the shape of
    # its JSON (which differs between lines).
    apps = machine.succeed("hc client call --port 4444 list-apps")
    machine.log("list-apps:\n" + apps)
    dna_hashes = sorted(set(re.findall(r"uhC0k[A-Za-z0-9_-]+", apps)))
    assert len(dna_hashes) == 1, f"expected one DNA hash, got {dna_hashes}"
    dna = dna_hashes[0]
    machine.log("dna hash: " + dna)

    # base64url of the JSON document `null`, which the gateway
    # transcodes to msgpack nil: the payload a zero-argument zome
    # function takes.
    PAYLOAD = "bnVsbA%3D%3D"

    def call(fn):
        url = (
            f"http://127.0.0.1:8090/{dna}/dino-adventure"
            f"/dino_adventure/{fn}?payload={PAYLOAD}"
        )
        code = machine.succeed(
            f"curl -s -o /tmp/body -w '%{{http_code}}' '{url}'"
        ).strip()
        body = machine.succeed("cat /tmp/body")
        machine.log(f"GET {fn} -> {code} {body}")
        return code, body

    # ---- the allowed read function answers 200 with JSON ----
    code, body = call("get_all_dinos_local")
    assert code == "200", f"allowed function answered {code}: {body}"
    machine.succeed("jq -e . /tmp/body >/dev/null")
    assert body.strip() == "[]", f"expected an empty dino list, got {body}"

    # ---- a function outside the allow list answers 403 ----
    code, body = call("get_all_dinos")
    assert code == "403", f"unallowed function answered {code}: {body}"
    machine.succeed("jq -e .error /tmp/body >/dev/null")
  '';
}
