# Called from nix/checks.nix with the per-system arguments of
# nix/shared.nix.
# The metrics jq against replies a bare conductor in a VM never
# produces: live connections, nested blocked_message_counts, installed
# apps, and a peer disconnecting between two runs. One malformed line
# makes node_exporter drop the whole textfile, so the output must pass
# promtool as well as carry the right sums.
{
  jqLib,
  pkgs,
  ...
}:
pkgs.runCommand "conductor-metrics-jq" {
  nativeBuildInputs = [pkgs.jq pkgs.prometheus.cli];
} ''
  cat > busy.json <<'EOF'
  {"transport_stats":{"backend":"iroh","peer_urls":["u1","u2"],
    "connections":[
      {"pub_key":"a","send_message_count":3,"send_bytes":100,"recv_message_count":4,"recv_bytes":200,"opened_at_s":1,"is_direct":true},
      {"pub_key":"b","send_message_count":5,"send_bytes":50,"recv_message_count":1,"recv_bytes":10,"opened_at_s":2,"is_direct":false}]},
   "blocked_message_counts":{"space1":{"reasonA":{"incoming":2,"outgoing":3}},"space2":{"reasonB":{"incoming":1,"outgoing":0}}}}
  EOF
  # b has disconnected and a has moved 20 more bytes; c is new, and
  # a reconnected under a new opened_at_s is a new connection too.
  cat > later.json <<'EOF'
  {"transport_stats":{"backend":"iroh","peer_urls":["u1"],
    "connections":[
      {"pub_key":"a","send_message_count":4,"send_bytes":120,"recv_message_count":4,"recv_bytes":200,"opened_at_s":1,"is_direct":true},
      {"pub_key":"c","send_message_count":1,"send_bytes":7,"recv_message_count":0,"recv_bytes":0,"opened_at_s":9,"is_direct":false}]},
   "blocked_message_counts":{}}
  EOF
  cat > apps.json <<'EOF'
  [{"installed_app_id":"x","status":{"type":"enabled"}},
   {"installed_app_id":"y","status":{"type":"disabled","value":{"reason":"user"}}},
   {"installed_app_id":"z","status":{"type":"awaiting_memproofs"}}]
  EOF

  # prev is a state file's contents; prints the textfile and leaves
  # the new state in state.json, as the timer's script does.
  run() {
    jq -c --argjson prev "$2" -f ${jqLib}/conductor-counters.jq < "$1" > state.json
    jq -r -L ${jqLib} --arg conductor "''${4:-Workshop}" --argjson up 1 --argjson now 1700000000 \
      --argjson totals "$(jq -c .totals state.json)" --argjson apps "$3" \
      -f ${jqLib}/conductor-metrics.jq < "$1"
  }

  echo '{}' > empty.json
  for input in busy.json empty.json; do
    for apps in null '[]' "$(cat apps.json)"; do
      run "$input" '{}' "$apps" > out.prom
      cat out.prom
      promtool check metrics < out.prom
    done
  done

  run busy.json '{}' "$(cat apps.json)" > out.prom
  grep -qx 'holochain_conductor_blocked_messages_total{conductor="Workshop"} 6' out.prom
  grep -qx 'holochain_conductor_peer_connections{conductor="Workshop"} 2' out.prom
  grep -qx 'holochain_conductor_direct_peer_connections{conductor="Workshop"} 1' out.prom
  grep -qx 'holochain_conductor_network_sent_bytes_total{conductor="Workshop"} 150' out.prom
  grep -qx 'holochain_conductor_apps{conductor="Workshop",status="enabled"} 1' out.prom
  grep -qx 'holochain_conductor_apps{conductor="Workshop",status="disabled"} 1' out.prom
  grep -qx 'holochain_conductor_apps{conductor="Workshop",status="awaiting_memproofs"} 1' out.prom

  # The totals only go up: 150 + a's 20 more + c's 7, although b and
  # its 50 bytes are gone from the reply.
  run later.json "$(cat state.json)" null > out.prom
  cat out.prom
  grep -qx 'holochain_conductor_network_sent_bytes_total{conductor="Workshop"} 177' out.prom
  grep -qx 'holochain_conductor_network_sent_messages_total{conductor="Workshop"} 10' out.prom
  grep -qx 'holochain_conductor_network_received_bytes_total{conductor="Workshop"} 210' out.prom
  if grep -q '^holochain_conductor_apps' out.prom; then
    echo "an unanswered list-apps must not read as zero apps" >&2
    exit 1
  fi

  # A down conductor answers nothing: the totals hold.
  run empty.json "$(cat state.json)" '[]' > out.prom
  grep -qx 'holochain_conductor_network_sent_bytes_total{conductor="Workshop"} 177' out.prom
  grep -qx 'holochain_conductor_apps{conductor="Workshop",status="enabled"} 0' out.prom
  grep -qx 'holochain_conductor_apps{conductor="Workshop",status="disabled"} 0' out.prom

  # ...and the connections it held survive the silence: when it
  # answers again, only what moved since counts. a sent 5 more
  # bytes and c 3 more, so 177 + 8, not 177 + a's and c's whole
  # lifetimes.
  cat > grown.json <<'EOF'
  {"transport_stats":{"backend":"iroh","peer_urls":["u1"],
    "connections":[
      {"pub_key":"a","send_message_count":5,"send_bytes":125,"recv_message_count":4,"recv_bytes":200,"opened_at_s":1,"is_direct":true},
      {"pub_key":"c","send_message_count":2,"send_bytes":10,"recv_message_count":0,"recv_bytes":0,"opened_at_s":9,"is_direct":false}]},
   "blocked_message_counts":{}}
  EOF
  run grown.json "$(cat state.json)" null > out.prom
  cat out.prom
  grep -qx 'holochain_conductor_network_sent_bytes_total{conductor="Workshop"} 185' out.prom
  grep -qx 'holochain_conductor_network_sent_messages_total{conductor="Workshop"} 12' out.prom
  grep -qx 'holochain_conductor_network_received_bytes_total{conductor="Workshop"} 210' out.prom

  # Every line names its conductor, and a name is free text: a
  # quote, a backslash and a newline in it are escaped, and no line
  # of the file is left without the label.
  run busy.json '{}' "$(cat apps.json)" "$(printf 'Mo"ss\\\nx')" > odd.prom
  cat odd.prom
  promtool check metrics < odd.prom
  grep -qxF 'holochain_conductor_up{conductor="Mo\"ss\\\nx"} 1' odd.prom
  grep -qxF 'holochain_conductor_apps{conductor="Mo\"ss\\\nx",status="enabled"} 1' odd.prom
  if grep -v '^#' odd.prom | grep -vF '{conductor="Mo\"ss\\\nx"'; then
    echo "a sample line without the conductor label" >&2
    exit 1
  fi
  touch $out
''
