# Moved verbatim from flake.nix (AD1); called from nix/checks.nix with the
# shared per-system arguments of nix/shared.nix.
{
  adminCall,
  edgenodeNode,
  hcOnPath,
  metricsTest,
  pkgs,
  roomToWork,
  ...
}: {
  name,
  line,
  appId,
  happ,
  nodeExtra ? {},
}:
pkgs.testers.nixosTest {
  inherit name;
  nodes.machine = {
    imports = [edgenodeNode hcOnPath roomToWork nodeExtra];
    services.holochain-edgenode = {
      enable = true;
      appPort = 8888;
      happs.${appId} = {
        src = happ;
        networkSeed = "ci-test-seed";
      };
      # The per-DHT series need an installed app to have a DHT at
      # all, so they are asserted here rather than in metricsTest.
      metricsExporter.enable = true;
      conductorMetrics.enable = true;
    };
  };
  testScript = ''
    import json
    import re

    # The bare app id also appears in the embedded manifest, so counting
    # installations means counting the installed_app_id key. Both lines
    # emit byte-identical JSON for these two.
    APP_KEY = '"installed_app_id":"${appId}"'
    ENABLED = '"status":{"type":"enabled"}'


    def assert_installed_once(stage):
        machine.wait_for_unit("holochain-conductor.service")
        machine.wait_for_unit("holochain-happ-installer.service")
        machine.wait_for_open_port(8888)

        result = machine.succeed(
            "systemctl show -p Result --value holochain-happ-installer.service"
        ).strip()
        assert result == "success", f"[{stage}] installer Result={result}"

        apps = machine.succeed("${adminCall.${line}} list-apps")
        assert APP_KEY in apps, f"[{stage}] app id missing from list-apps: {apps}"
        assert ENABLED in apps, f"[{stage}] app is not enabled: {apps}"

        count = apps.count(APP_KEY)
        assert count == 1, f"[{stage}] app listed {count} times, expected exactly 1"
        machine.log(f"[{stage}] app is installed once and enabled")


    assert_installed_once("first boot")

    # A cold boot is the real test of both the idempotent installer and
    # the generated lair passphrase: neither may need a human.
    machine.shutdown()
    machine.start()

    assert_installed_once("after reboot")

    # ---- one per-DHT series set for every cell of the app ----
    # The cells the conductor itself reports, not a list written here.
    apps = json.loads(machine.succeed("${adminCall.${line}} list-apps"))
    cells = [
        (role, cell["value"]["cell_id"]["dna_hash"])
        for app in apps
        if app["installed_app_id"] == "${appId}"
        for role, infos in app["cell_info"].items()
        for cell in infos
        if "cell_id" in cell.get("value", {})
    ]
    machine.log(f"cells of ${appId}: {cells}")
    assert cells, f"no cell with a DNA hash in list-apps: {apps}"

    machine.wait_for_unit("prometheus-node-exporter.service")
    machine.wait_until_succeeds(
        "curl -s localhost:9100/metrics"
        " | grep '^holochain_dht_peers{' | grep -F 'app_id=\"${appId}\"'",
        timeout=180,
    )
    series = machine.succeed("curl -s localhost:9100/metrics | grep '^holochain_'")
    machine.log("holochain series on /metrics:\n" + series)

    # The conductor series are still there next to them.
    assert 'holochain_conductor_up{conductor="Holochain"} 1' in series, series
    assert 'holochain_conductor_apps{conductor="Holochain",status="enabled"} 1' in series, series

    # node_exporter re-sorts labels, so a series is keyed by its
    # name and its label set rather than by the line's spelling.
    values = {}
    rows = []
    for line in series.splitlines():
        m = re.fullmatch(r'(\w+)(?:\{(.*)\})? (\S+)', line)
        assert m, f"unparsable line: {line}"
        labels = frozenset(re.findall(r'(\w+)="([^"]*)"', m.group(2) or ""))
        values[m.group(1) + str(sorted(labels))] = m.group(3)
        rows.append((m.group(1), dict(labels), m.group(3)))

    # The app is named once, enabled, by a name that is not its id's hash.
    app_info = [
        r for r in rows
        if r[0] == "holochain_app_info" and r[1].get("app_id") == "${appId}"
    ]
    assert len(app_info) == 1, f"holochain_app_info for ${appId}: {app_info}"
    assert app_info[0][1]["status"] == "enabled", app_info
    assert app_info[0][1]["conductor"] == "Holochain", app_info
    assert app_info[0][1]["app_name"] != "", app_info

    for role, dna in cells:
        key = {("conductor", "Holochain"), ("app_id", "${appId}"), ("role", role), ("dna", dna)}
        labels = str(sorted(key))
        # One name row per DHT, keyed like its data series, whose
        # names carry no hash and no Moss escape.
        info = [
            r for r in rows
            if r[0] == "holochain_dht_info" and key <= set(r[1].items())
        ]
        assert len(info) == 1, f"{len(info)} holochain_dht_info rows for {key}:\n{series}"
        for label in ["app_name", "app_kind", "part_name", "network_label"]:
            value = info[0][1][label]
            assert "uhC" not in value and "$" not in value, f"{label}={value!r}"
        assert info[0][1]["network_label"] != "", info
        for name in [
            "holochain_dht_peers",
            "holochain_dht_local_ops",
            "holochain_dht_peer_ops",
            "holochain_dht_pending_fetches",
            "holochain_dht_seconds_since_gossip",
            "holochain_dht_completed_rounds_total",
            "holochain_dht_peer_timeouts_total",
        ]:
            assert name + labels in values, f"{name}{labels} missing:\n{series}"
        # A node alone on its network has no peer and has never
        # gossiped: 0 peers and -1, not an age since the epoch.
        assert values["holochain_dht_peers" + labels] == "0", values
        assert values["holochain_dht_seconds_since_gossip" + labels] == "-1", values
  '';
}
