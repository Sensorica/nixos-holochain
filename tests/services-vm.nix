# Moved verbatim from flake.nix (AD1); called from nix/checks.nix with the
# shared per-system arguments of nix/shared.nix.
# One machine running an edgenode, the HTTP gateway, Grafana and, when
# `bootstrap` is true, the local bootstrap and relay. The pass
# condition is what a person reads through Grafana's own query API:
# the node page's "Is each service on this machine running?" names
# every service the enabled modules installed, and nothing else, each
# Running; with
# bootstrap, the server frozen reads Not answering while systemd still
# says active, and stopped reads Stopped, the room screen's tile for
# the machine turning to A service is down both times.
#
# `expectBootstrap` exists for the falsifiers: a test that expects
# the bootstrap server on a machine without it, or not on one with it,
# has to fail (legacyPackages.falsifiers).
{
  edgenodeNode,
  grafanaTestPassword,
  pkgs,
  roomToWork,
  self,
  system,
  ...
}: {
  name,
  bootstrap ? true,
  expectBootstrap ? bootstrap,
}:
pkgs.testers.nixosTest {
  inherit name;
  nodes.machine = {
    imports = [
      edgenodeNode
      roomToWork
      self.nixosModules.holochain-grafana
      self.nixosModules.holochain-http-gateway
      self.nixosModules.holochain-bootstrap
    ];
    environment.systemPackages = [pkgs.jq];
    services.holochain-edgenode = {
      enable = true;
      metricsExporter.enable = true;
      conductorMetrics.enable = true;
    };
    services.holochain-http-gateway.enable = true;
    services.holochain-bootstrap.enable = bootstrap;
    systemd.tmpfiles.rules = [
      "d /var/lib/secrets 0700 root root - -"
      "f /var/lib/secrets/grafana-admin-password 0400 root root - ${grafanaTestPassword}"
    ];
    services.holochain-grafana = {
      enable = true;
      adminPasswordFile = "/var/lib/secrets/grafana-admin-password";
      scrapeTargets.machine.address = "127.0.0.1:9100";
    };
  };
  testScript = ''
    import base64
    import json

    EXPECT_BOOTSTRAP = ${
      if expectBootstrap
      then "True"
      else "False"
    }
    BOOTSTRAP = "Local bootstrap and relay"
    RUNNING, NOT_ANSWERING, STOPPED, FAILED = 6, 2, 1, 0
    TILE_RUNNING, TILE_SERVICE_DOWN = 4, 2

    machine.wait_for_unit("grafana.service")
    machine.wait_for_unit("prometheus.service")
    machine.wait_for_unit("holochain-conductor.service")
    machine.wait_for_open_port(3000)


    def grafana(path):
        return json.loads(machine.succeed(
            "curl -sf -u admin:${grafanaTestPassword}"
            f" 'http://localhost:3000{path}'"
        ))


    def target(uid, title):
        panels = grafana(f"/api/dashboards/uid/{uid}")["dashboard"]["panels"]
        panels = panels + [p for row in panels for p in row.get("panels", [])]
        expr = next(p for p in panels if p["title"] == title and p["type"] != "row")["targets"][0]["expr"]
        expr = expr.replace("$node", "machine").replace("$site", ".*")
        assert "$" not in expr, expr
        return expr


    # The queries the pages run, as Grafana serves them.
    services_expr = target("holochain-node", "Is each service on this machine running?")
    tile_expr = target("holochain-now", "Which machines are on?")
    down_expr = target("holochain-fleet", "Which services are not running?")
    problems_expr = target("holochain-fleet", "What needs a human?")
    machine.log(f"services query: {services_expr}")


    def ds(expr, name):
        """One instant query through Grafana's /api/ds/query, as {labels: value}."""
        body = {
            "from": "now-5m",
            "to": "now",
            "queries": [{
                "refId": "A",
                "datasource": {"type": "prometheus", "uid": "holochain-prometheus"},
                "expr": expr,
                "instant": True,
                "range": False,
                "intervalMs": 15000,
                "maxDataPoints": 100,
            }],
        }
        encoded = base64.b64encode(json.dumps(body).encode()).decode()
        machine.succeed(f"echo {encoded} | base64 -d > /tmp/{name}.json")
        reply = json.loads(machine.succeed(
            "curl -s -u admin:${grafanaTestPassword} -H 'Content-Type: application/json'"
            f" -X POST --data @/tmp/{name}.json http://localhost:3000/api/ds/query"
        ))
        result = reply["results"]["A"]
        assert result.get("error") is None, result
        return [
            (frame["schema"]["fields"][1].get("labels", {}), frame["data"]["values"][1][-1])
            for frame in result.get("frames", [])
            if frame["data"]["values"] and frame["data"]["values"][1]
        ]


    def services():
        """The node page's services table: {service name: state code}."""
        return {labels["service"]: value for labels, value in ds(services_expr, "services")}


    def tile():
        return {labels["node"]: value for labels, value in ds(tile_expr, "tile")}.get("machine")


    expected = {
        "Holochain conductor", "Holochain readings (timer)", "HTTP gateway",
        "Metrics database", "Dashboards", "Machine readings", "Nix",
    } | ({BOOTSTRAP} if EXPECT_BOOTSTRAP else set())


    def all_running(rows, want):
        return set(rows) == want and all(v == RUNNING for v in rows.values())


    # The check must fail on an answer that is not the one wanted:
    # one service short, one in another state, one too many.
    sample = {n: RUNNING for n in expected}
    assert all_running(sample, expected)
    assert not all_running({n: v for n, v in sample.items() if n != "HTTP gateway"}, expected)
    assert not all_running({**sample, "HTTP gateway": STOPPED}, expected)
    assert not all_running({**sample, "Remote login": RUNNING}, expected)

    last = {}


    def settled(_):
        global last
        last = services()
        return all_running(last, expected)


    try:
        retry(settled, timeout_seconds=300)
    finally:
        machine.log("services on the node page: " + json.dumps(last, sort_keys=True))
    # The services can settle before the conductor's first readings
    # reach Prometheus, and until then the machine has no Holochain
    # to show.
    retry(lambda _: tile() == TILE_RUNNING, timeout_seconds=180)

    if not EXPECT_BOOTSTRAP:
        # Nothing of the server anywhere: no unit, no health reading.
        assert BOOTSTRAP not in services()
        machine.fail("systemctl cat holochain-bootstrap.service")
        machine.fail("curl -s localhost:9100/metrics | grep -q '^holochain_service_healthy'")
    else:
        health = machine.succeed("curl -s localhost:9100/metrics | grep '^holochain_service_healthy'")
        machine.log("health reading: " + health)
        assert 'holochain_service_healthy{name="holochain-bootstrap.service"} 1' in health, health


        def reads(state):
            return lambda _: services().get(BOOTSTRAP) == state


        def listed_down(state):
            return any(
                labels.get("service") == BOOTSTRAP and value == state
                for labels, value in ds(down_expr, "down")
            )


        def problem(sentence):
            return any(labels.get("problem") == sentence for labels, _ in ds(problems_expr, "problems"))


        # Running but not answering: the server frozen, its unit
        # still active. The same checks fail while it answers.
        assert not reads(NOT_ANSWERING)(None)
        assert not listed_down(NOT_ANSWERING)
        pid = machine.succeed("systemctl show -p MainPID --value holochain-bootstrap.service").strip()
        machine.succeed(f"kill -STOP {pid}")
        retry(reads(NOT_ANSWERING), timeout_seconds=180)
        assert machine.succeed("systemctl is-active holochain-bootstrap.service").strip() == "active"
        assert listed_down(NOT_ANSWERING)
        assert problem(f"{BOOTSTRAP} is not answering")
        assert tile() == TILE_SERVICE_DOWN, tile()
        machine.log("frozen: Not answering, while systemd says active")

        machine.succeed(f"kill -CONT {pid}")
        retry(reads(RUNNING), timeout_seconds=180)
        retry(lambda _: tile() == TILE_RUNNING, timeout_seconds=60)

        # Stopped.
        assert not reads(STOPPED)(None)
        machine.succeed("systemctl stop holochain-bootstrap.service")
        retry(reads(STOPPED), timeout_seconds=120)
        assert listed_down(STOPPED)
        assert problem(f"{BOOTSTRAP} is stopped")
        assert tile() == TILE_SERVICE_DOWN, tile()
        machine.log("stopped: Stopped")

        # Failing at every start: systemd restarts it every
        # RestartSec and calls it activating in between, so only the
        # restart count tells the loop from a slow start.
        loop = "failed and systemd is restarting it"
        assert not reads(FAILED)(None)
        assert not problem(f"{BOOTSTRAP} {loop}")
        machine.succeed(
            "mkdir -p /run/systemd/system/holochain-bootstrap.service.d"
            " && printf '[Service]\\nExecStart=\\nExecStart=/bin/sh -c \"exit 1\"\\n'"
            " > /run/systemd/system/holochain-bootstrap.service.d/fail.conf"
            " && systemctl daemon-reload"
            " && systemctl start --no-block holochain-bootstrap.service"
        )
        retry(lambda _: problem(f"{BOOTSTRAP} {loop}"), timeout_seconds=180)
        retry(reads(FAILED), timeout_seconds=60)
        machine.log("systemd: " + machine.succeed(
            "systemctl show -p ActiveState -p SubState -p NRestarts holochain-bootstrap.service"
        ).replace("\n", " "))
        assert int(machine.succeed(
            "systemctl show -p NRestarts --value holochain-bootstrap.service"
        )) > 1
        assert listed_down(FAILED)
        assert tile() == TILE_SERVICE_DOWN, tile()
        machine.log("restarting at every failure: Failed")
  '';
}
