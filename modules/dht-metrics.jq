# Turns the conductor's `list-apps` and `dump-network-metrics --include-dht-summary`
# replies into node_exporter textfile series, one set per DHT the conductor is in.
#
# Run with -n; both replies arrive on stdin, list-apps first, each one either the
# reply or null when that call did not answer. They come through stdin rather than
# --argjson because a list-apps reply carries every DNA's properties and grows past
# the 128 KiB a single command-line argument may hold (Linux MAX_ARG_STRLEN); a
# Moss node with three apps already answers 110 KB.
#
# list-apps: [{installed_app_id, cell_info: {<role>: [{type, value: {cell_id:
#   {dna_hash, agent_pub_key}}}]}}]. Provisioned and cloned cells carry a cell_id;
#   stem cells do not and are skipped.
# dump-network-metrics: {<dna_hash>: {fetch_state_summary: {pending_requests:
#   {<op id>: [peer url]}}, gossip_state_summary: {peer_meta: {<peer url>:
#   {last_gossip_timestamp (microseconds), completed_rounds, dht_op_count,
#   peer_timeouts, ...}}, local_op_count, ...}, local_agents}}. Kitsune2's
#   GossipStateSummary, PeerMeta and FetchStateSummary are declared identically in
#   kitsune2_api 0.4.1 (the 0.6 line) and 0.5.0 (the 0.7 line); the shape above was
#   read from a Holochain 0.6.1 conductor on 2026-09-27.
#
# $now is the scrape time in seconds since the epoch.
#
# A cell whose DNA the reply does not mention is in no network the conductor
# reports right now, and gets no series rather than zeros that would read as a
# DHT with no peers and no data. When either call did not answer, no DHT gets
# any series, for the same reason.
#
# Every sample line must end in a number and every label value must be quoted and
# escaped: node_exporter drops the whole textfile on one bad line, and with it
# every holochain_conductor_* series.

def metric($name; $help; $type):
  "# HELP \($name) \($help)", "# TYPE \($name) \($type)";

def num: if type == "number" then . else 0 end;

def escape: tostring | gsub("\\\\"; "\\\\") | gsub("\""; "\\\"") | gsub("\n"; "\\n");

def labels: "{app=\"\(.app | escape)\",role=\"\(.role | escape)\",dna=\"\(.dna | escape)\"}";

input as $apps
| input as $metrics
| if ($apps | type) != "array" or ($metrics | type) != "object" then empty
  else
    [ $apps[]
      | (.installed_app_id // "") as $app
      | (.cell_info // {}) | to_entries[]
      | .key as $role
      | .value[]?
      | (.value.cell_id.dna_hash? // empty) as $dna
      | select($dna | type == "string")
      | select($metrics | has($dna))
      | ($metrics[$dna] // {}) as $m
      | ($m.gossip_state_summary // {}) as $g
      | [($g.peer_meta // {}) | .[]? | objects] as $peers
      | ([$peers[].last_gossip_timestamp | num] | max // 0) as $last
      | {
          app: $app, role: $role, dna: $dna,
          peers: ($peers | length),
          local_ops: ($g.local_op_count | num),
          peer_ops: ([$peers[].dht_op_count | num] | max // 0),
          pending: (($m.fetch_state_summary.pending_requests // {}) | if type == "object" then length else 0 end),
          since: (if $last > 0 then ([($now - ($last / 1000000)) | floor, 0] | max) else -1 end),
          rounds: ([$peers[].completed_rounds | num] | add // 0),
          timeouts: ([$peers[].peer_timeouts | num] | add // 0)
        }
    ] as $rows
    | if $rows == [] then empty
      else
        def series($name; $help; $type; $field):
          metric($name; $help; $type),
          ($rows[] | "\($name)\(labels) \(.[$field])");
        series("holochain_dht_peers";
          "Peers this conductor keeps gossip state for in one DHT (entries in gossip_state_summary.peer_meta).";
          "gauge"; "peers"),
        series("holochain_dht_local_ops";
          "DHT operations this conductor holds for one DHT (gossip_state_summary.local_op_count).";
          "gauge"; "local_ops"),
        series("holochain_dht_peer_ops";
          "Largest DHT operation count any peer reported for one DHT; local_ops reaching it means this node holds as much as its best peer.";
          "gauge"; "peer_ops"),
        series("holochain_dht_pending_fetches";
          "Operations this conductor has asked peers for in one DHT and not yet received.";
          "gauge"; "pending"),
        series("holochain_dht_seconds_since_gossip";
          "Seconds since the last gossip round with any peer in one DHT; -1 when there has been none.";
          "gauge"; "since"),
        series("holochain_dht_completed_rounds_total";
          "Gossip rounds completed with peers in one DHT, summed over the peers currently known; drops when a peer is forgotten.";
          "counter"; "rounds"),
        series("holochain_dht_peer_timeouts_total";
          "Gossip rounds with peers in one DHT that timed out, summed over the peers currently known; drops when a peer is forgotten.";
          "counter"; "timeouts")
      end
  end
