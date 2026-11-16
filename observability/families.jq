# The one place a `# HELP` or `# TYPE` line of a holochain_* family is written.
#
# conductor-metrics.jq and dht-metrics.jq `include "families";` (run jq with
# `-L` pointing at this directory), so every textfile the exporter writes, for
# every conductor on a machine, declares each family with the same bytes.
#
# That is not tidiness. node_exporter's textfile collector merges every *.prom
# in its directory by family, and when two files give one family different HELP
# text it logs `inconsistent metric help text`, keeps the family from the first
# file only, and sets node_textfile_scrape_error to 1. Seen on node_exporter
# 1.11.1 on 2026-09-27 with two files declaring holochain_dht_peers: every
# series of the second file vanished. checks.metricsHelpAgreement holds the
# outputs of two differently shaped conductors to this.
#
# A HELP text is a constant: nothing about the conductor, the node or the app
# may go into it, since that is exactly what would differ between two files.

def families: {
  holochain_conductor_up: {
    type: "gauge",
    help: "1 when the conductor admin interface answered dump-network-stats, 0 otherwise."
  },
  holochain_conductor_peer_connections: {
    type: "gauge",
    help: "Transport connections the conductor currently holds to other peers."
  },
  holochain_conductor_direct_peer_connections: {
    type: "gauge",
    help: "Peer connections that upgraded from the relay to a direct connection."
  },
  holochain_conductor_peer_urls: {
    type: "gauge",
    help: "Peer URLs this conductor can currently be reached at."
  },
  holochain_conductor_network_sent_bytes_total: {
    type: "counter",
    help: "Bytes sent to peers since the counter state was created, including closed connections."
  },
  holochain_conductor_network_received_bytes_total: {
    type: "counter",
    help: "Bytes received from peers since the counter state was created, including closed connections."
  },
  holochain_conductor_network_sent_messages_total: {
    type: "counter",
    help: "Messages sent to peers since the counter state was created, including closed connections."
  },
  holochain_conductor_network_received_messages_total: {
    type: "counter",
    help: "Messages received from peers since the counter state was created, including closed connections."
  },
  holochain_conductor_blocked_messages_total: {
    type: "counter",
    help: "Messages the conductor blocked, incoming and outgoing, summed over every block reason."
  },
  holochain_conductor_metrics_scrape_timestamp_seconds: {
    type: "gauge",
    help: "Unix time at which this textfile was written."
  },
  holochain_conductor_apps: {
    type: "gauge",
    help: "Installed apps, by status type from list-apps."
  },
  holochain_app_info: {
    type: "gauge",
    help: "Always 1. Names one installed app for dashboards: app_name and app_kind as a person reads them, status from list-apps, or expected for an app Nix manages that the conductor did not list."
  },
  holochain_dht_info: {
    type: "gauge",
    help: "Always 1. Names one DHT for dashboards: the app, its kind, the part the role stands for, and the network label shown instead of any hash."
  },
  holochain_dht_peers: {
    type: "gauge",
    help: "Peers this conductor keeps gossip state for in one DHT (entries in gossip_state_summary.peer_meta)."
  },
  holochain_dht_local_ops: {
    type: "gauge",
    help: "DHT operations this conductor holds for one DHT (gossip_state_summary.local_op_count)."
  },
  holochain_dht_peer_ops: {
    type: "gauge",
    help: "Largest DHT operation count any peer reported for one DHT; local_ops reaching it means this node holds as much as its best peer."
  },
  holochain_dht_pending_fetches: {
    type: "gauge",
    help: "Operations this conductor has asked peers for in one DHT and not yet received."
  },
  holochain_dht_seconds_since_gossip: {
    type: "gauge",
    help: "Seconds since the last gossip round with any peer in one DHT; -1 when there has been none."
  },
  holochain_dht_completed_rounds_total: {
    type: "counter",
    help: "Gossip rounds completed with peers in one DHT, summed over the peers currently known; drops when a peer is forgotten."
  },
  holochain_dht_peer_timeouts_total: {
    type: "counter",
    help: "Gossip rounds with peers in one DHT that timed out, summed over the peers currently known; drops when a peer is forgotten."
  }
};

# The HELP and TYPE lines of one family. A name missing from the table is an
# error rather than a line made up on the spot, so a new series cannot bring
# its own HELP text past this file.
def family($name):
  (families[$name] // error("\($name) is not declared in families.jq"))
  | "# HELP \($name) \(.help)", "# TYPE \($name) \(.type)";

# A label value as the text format needs it: backslash, double quote and
# newline escaped. node_exporter drops the whole file on one bad line, so
# every label value either file writes goes through this.
def escape: tostring | gsub("\\\\"; "\\\\") | gsub("\""; "\\\"") | gsub("\n"; "\\n");
