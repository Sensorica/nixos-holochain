# Moved verbatim from flake.nix (AD1); called from nix/checks.nix with the
# shared per-system arguments of nix/shared.nix.
# The conductor gauges have to exist on both lines, and the only thing
# that differs between them is the admin call prefix. So this runs the
# module's own timer against a real conductor of each line rather than
# asserting that the prefix is right.
{
  edgenodeNode,
  pkgs,
  roomToWork,
  ...
}: {
  name,
  nodeExtra ? {},
}:
pkgs.testers.nixosTest {
  inherit name;
  nodes.machine = {
    imports = [edgenodeNode roomToWork nodeExtra];
    services.holochain-edgenode = {
      enable = true;
      metricsExporter.enable = true;
      conductorMetrics.enable = true;
    };
  };
  testScript = ''
    machine.wait_for_unit("holochain-conductor.service")
    machine.wait_for_unit("prometheus-node-exporter.service")
    machine.wait_for_unit("holochain-conductor-metrics.timer")

    machine.wait_until_succeeds(
        "curl -s localhost:9100/metrics | grep -F 'holochain_conductor_up{conductor=\"Holochain\"} 1'",
        timeout=180,
    )
    series = machine.succeed("curl -s localhost:9100/metrics | grep '^holochain_'")
    machine.log("holochain series on /metrics:\n" + series)

    # Every sample names its conductor, "Holochain" while
    # conductorMetrics.name is left at its default. The service
    # inventory is per unit, so only the conductor's own unit
    # carries a conductor there.
    readings = [l for l in series.splitlines() if not l.startswith("holochain_service_info")]
    assert len(readings) >= 10, f"too few conductor readings: {readings}"
    for line in readings:
        assert 'conductor="Holochain"' in line, f"no conductor label: {line}"
    conductor_unit = [l for l in series.splitlines() if l.startswith("holochain_service_info") and 'name="holochain-conductor.service"' in l]
    assert len(conductor_unit) == 1 and 'conductor="Holochain"' in conductor_unit[0], f"conductor unit without its conductor: {conductor_unit}"

    for name in [
        "holochain_conductor_up",
        "holochain_conductor_peer_connections",
        "holochain_conductor_direct_peer_connections",
        "holochain_conductor_peer_urls",
        "holochain_conductor_network_sent_bytes_total",
        "holochain_conductor_network_received_bytes_total",
        "holochain_conductor_network_sent_messages_total",
        "holochain_conductor_network_received_messages_total",
        "holochain_conductor_blocked_messages_total",
        "holochain_conductor_metrics_scrape_timestamp_seconds",
    ]:
        assert name in series, f"{name} missing:\n{series}"

    # list-apps answered on this line too, with no app installed; an
    # unanswered call would leave the line out rather than write 0.
    assert 'holochain_conductor_apps{conductor="Holochain",status="enabled"} 0' in series, series
  '';
}
