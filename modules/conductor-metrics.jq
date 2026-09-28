# Turns one `dump-network-stats` reply into node_exporter textfile format.
#
# The reply is Kitsune2's TransportStats
# (kitsune2 crates/api/src/transport.rs): { backend, peer_urls[],
# connections[ { pub_key, send_message_count, send_bytes, recv_message_count,
# recv_bytes, opened_at_s, is_direct } ] }, wrapped by Holochain together with
# blocked_message_counts. Identical on 0.6.3 and 0.7.0, verified against both
# binaries; see docs/architecture.md. blocked_message_counts nests (per space,
# then per reason, ending in {incoming, outgoing}), so its total sums every
# number at any depth: a line that is not a number would make node_exporter
# drop the whole file, holochain_conductor_up included.
#
# $conductor names the conductor, and every line carries it as a label: one
# machine can run more than one conductor (an edgenode's own next to a Moss
# node), and their series must not merge.
# $up is 1 when the admin interface answered and 0 when it did not, so the
# series never disappears from the dashboard when a conductor is down.
# $now is the scrape time in seconds since the epoch.
# $totals is the running byte and message totals conductor-counters.jq keeps
# across runs; the reply's own counts cover only the connections open right
# now, and would go down whenever a peer disconnects.
# $apps is the list-apps reply, or null when that call did not answer, in which
# case no holochain_conductor_apps line is written rather than a false zero.
# Every installed app counts under its status type; enabled and disabled are
# always written, so an empty conductor reads 0 rather than nothing.
#
# The HELP and TYPE lines come from families.jq, shared with dht-metrics.jq.

include "families";

def conductor: "conductor=\"\($conductor | escape)\"";

def metric($name; $value):
  family($name), "\($name){\(conductor)} \($value)";

def apps:
  if $apps == null then empty
  else
    ([$apps[] | .status.type // "unknown" | tostring | ascii_downcase | gsub("[^a-z_]"; "_")]
      | reduce .[] as $s ({enabled: 0, disabled: 0}; .[$s] += 1)) as $by
    | family("holochain_conductor_apps"),
      ($by | to_entries[] | "holochain_conductor_apps{\(conductor),status=\"\(.key)\"} \(.value)")
  end;

(.transport_stats // {}) as $t
| ($t.connections // []) as $c
| ($t.peer_urls // []) as $u
| (.blocked_message_counts // {}) as $b
| metric("holochain_conductor_up"; $up),
  metric("holochain_conductor_peer_connections"; ($c | length)),
  metric("holochain_conductor_direct_peer_connections"; ([$c[] | select(.is_direct)] | length)),
  metric("holochain_conductor_peer_urls"; ($u | length)),
  metric("holochain_conductor_network_sent_bytes_total"; ($totals.send_bytes // 0)),
  metric("holochain_conductor_network_received_bytes_total"; ($totals.recv_bytes // 0)),
  metric("holochain_conductor_network_sent_messages_total"; ($totals.send_message_count // 0)),
  metric("holochain_conductor_network_received_messages_total"; ($totals.recv_message_count // 0)),
  metric("holochain_conductor_blocked_messages_total"; ([$b | .. | numbers] | add // 0)),
  metric("holochain_conductor_metrics_scrape_timestamp_seconds"; $now),
  apps
