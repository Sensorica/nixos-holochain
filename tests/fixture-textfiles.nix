# The two fixture conductors as textfiles, the way holochain-conductor-exporter
# writes them, at the capture's own clock: Workshop (the homelab's 0.6.3
# edgenode conductor, tests/fixtures/edgenode-0_6_3) and Moss (a Moss group
# node, tests/fixtures/dht-0_6_1), each with the names file tests/metrics.nix
# gives it.
#
# The clock is fixed at 1790484800, the moment checks.dhtMetricsJq reads the
# replies at, so every gossip age is the captured one rather than one that
# grows with the time since the capture: the rule tests and vmTestGrafana
# can then say which state each DHT is in. The freshness timestamp is written
# as that same moment; a reader sets it to its own clock.
{
  pkgs,
  # The exporter's jq programs (packages/holochain-conductor-exporter.nix).
  jqLib,
  # The names files of tests/metrics.nix: {workshop, moss}.
  names,
}:
pkgs.runCommand "holochain-fixture-textfiles" {
  nativeBuildInputs = [pkgs.jq pkgs.prometheus.cli];
} ''
  write() {
    local replies=$1 names=$2 conductor=$3
    # Only the status of each app reaches conductor-metrics.jq, as in the
    # exporter, whose list-apps reply is too long for one argument.
    echo '{}' | jq -r -L ${jqLib} --arg conductor "$conductor" --argjson up 1 --argjson now 1790484800 \
      --argjson totals '{}' --argjson apps "$(jq -c '[.[] | {status: {type: .status.type}}]' "$replies/list-apps.json")" \
      -f ${jqLib}/conductor-metrics.jq
    printf '%s\n%s\n%s\n' "$(cat "$replies/list-apps.json")" "$(cat "$replies/dump-network-metrics.json")" "$(cat "$names")" \
      | jq -n -r -L ${jqLib} --arg conductor "$conductor" --argjson now 1790484800 -f ${jqLib}/dht-metrics.jq
  }
  mkdir $out
  write ${./fixtures/edgenode-0_6_3} ${names.workshop} Workshop > $out/workshop.prom
  write ${./fixtures/dht-0_6_1} ${names.moss} Moss > $out/moss.prom
  for f in $out/*.prom; do
    promtool check metrics < "$f"
    grep -qx 'holochain_conductor_metrics_scrape_timestamp_seconds{conductor="[A-Za-z]*"} 1790484800' "$f"
  done
  test "$(grep -c '^holochain_dht_peers{' $out/workshop.prom)" = 4
  test "$(grep -c '^holochain_dht_peers{' $out/moss.prom)" = 7
''
