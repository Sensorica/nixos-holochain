# Turns one `dump-network-stats` reply into node_exporter textfile format.
#
# The reply is Kitsune2's TransportStats
# (kitsune2 crates/api/src/transport.rs): { backend, peer_urls[],
# connections[ { pub_key, send_message_count, send_bytes, recv_message_count,
# recv_bytes, opened_at_s, is_direct } ] }, wrapped by Holochain together with
# blocked_message_counts. Identical on 0.6.3 and 0.7.0, verified against both
# binaries; see docs/architecture.md.
#
# $up is 1 when the admin interface answered and 0 when it did not, so the
# series never disappears from the dashboard when a conductor is down.
# $now is the scrape time in seconds since the epoch.

def metric($name; $help; $type; $value):
  "# HELP \($name) \($help)",
  "# TYPE \($name) \($type)",
  "\($name) \($value)";

def total(f): [.[] | f] | add // 0;

(.transport_stats // {}) as $t
| ($t.connections // []) as $c
| ($t.peer_urls // []) as $u
| (.blocked_message_counts // {}) as $b
| metric(
    "holochain_conductor_up";
    "1 when the conductor admin interface answered dump-network-stats, 0 otherwise.";
    "gauge"; $up),
  metric(
    "holochain_conductor_peer_connections";
    "Transport connections the conductor currently holds to other peers.";
    "gauge"; ($c | length)),
  metric(
    "holochain_conductor_direct_peer_connections";
    "Peer connections that upgraded from the relay to a direct connection.";
    "gauge"; ([$c[] | select(.is_direct)] | length)),
  metric(
    "holochain_conductor_peer_urls";
    "Peer URLs this conductor can currently be reached at.";
    "gauge"; ($u | length)),
  metric(
    "holochain_conductor_network_sent_bytes_total";
    "Bytes sent over all current peer connections.";
    "counter"; ($c | total(.send_bytes))),
  metric(
    "holochain_conductor_network_received_bytes_total";
    "Bytes received over all current peer connections.";
    "counter"; ($c | total(.recv_bytes))),
  metric(
    "holochain_conductor_network_sent_messages_total";
    "Messages sent over all current peer connections.";
    "counter"; ($c | total(.send_message_count))),
  metric(
    "holochain_conductor_network_received_messages_total";
    "Messages received over all current peer connections.";
    "counter"; ($c | total(.recv_message_count))),
  metric(
    "holochain_conductor_blocked_messages_total";
    "Messages the conductor refused, summed over every block reason.";
    "counter"; ([$b[]] | add // 0)),
  metric(
    "holochain_conductor_metrics_scrape_timestamp_seconds";
    "Unix time at which this textfile was written.";
    "gauge"; $now)
