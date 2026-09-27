# modules/holochain-rules.nix
#
# The Prometheus recording rules every Holochain dashboard reads, as the
# attrset of one rule file. holochain-grafana renders it with its `states`
# options and hands it to Prometheus; checks.holochainRules runs promtool's
# rule tests on the file that module renders.
#
# Every state is computed here once, so no two dashboards can disagree about
# what "In step" means. Codes run from worst to best, so `min` over any set of
# them picks the worst item:
#
#   DHT (one DNA of one app on one conductor), and app (its worst DHT):
#     0 Not running         the app should be here and Holochain does not report it
#     1 No fresh readings   the conductor's readings are older than staleAfterSeconds
#     2 Lost contact        nobody connected although someone was in the history
#                           window or another node of this fleet runs the DNA; or
#                           peers known and nothing heard for silentAfterSeconds
#     3 No one else yet     nobody connected, ever, and no other node runs the DNA
#     4 Catching up         connected, holding under inStepShare of the best peer's
#                           data on average over shareWindow
#     5 In step             connected and holding at least that share
#
#   Conductor: 1 Holochain not answering, 2 No fresh readings, 3 Running.
#   Node: 0 Unreachable, then its worst conductor, else 4 No Holochain here.
#
# Data series carry machine keys only. Names come from holochain_dht_info,
# joined on the full key of a DHT: instance, conductor, app_id, role and dna.
# A join on fewer labels is a many-to-many error as soon as an app has a clone
# cell, which shares its conductor, app id and role with the cell it was
# cloned from.
#
# PromQL notes for reading the expressions: `and` and `unless` bind tighter
# than `or`; each branch of a ladder multiplies by 0 before adding its code,
# which drops the metric name, so `or` tells the branches apart by their
# labels alone and the first branch that matches a DHT wins.
{
  # How often Prometheus evaluates the group, its scrape interval.
  interval,
  # services.holochain-grafana.states.
  states,
}: let
  num = builtins.toJSON;

  stale = num states.staleAfterSeconds;
  silent = num states.silentAfterSeconds;
  share = num states.inStepShare;
  inherit (states) shareWindow historyWindow;

  # The full key of a DHT series, and the join that names one.
  dht = "instance, conductor, app_id, role, dna";
  named = expr: ''
    (${expr})
      * on (${dht}) group_left (app_name, app_kind, part_name, network_label)
    holochain:dht_names'';

  # Filesystems that are not a disk someone can fill.
  virtualFs = ''fstype!~"tmpfs|ramfs|overlay|squashfs|nsfs"'';

  problem = text: expr: ''label_replace(${expr}, "problem", "${text}", "", "")'';
in {
  groups = [
    {
      name = "holochain";
      inherit interval;
      rules = [
        # 1 when the conductor's exporter wrote within staleAfterSeconds.
        {
          record = "holochain:conductor_fresh";
          expr = "(time() - holochain_conductor_metrics_scrape_timestamp_seconds) < bool ${stale}";
        }

        # The names of every DHT, with a fallback for one that has no info
        # row, so it is still drawn, as "Unnamed app", and still counted.
        {
          record = "holochain:dht_names";
          expr = ''
            holochain_dht_info
            or on (${dht})
            label_replace(
              label_replace(
                label_replace(holochain_dht_peers * 0 + 1, "app_name", "Unnamed app", "", ""),
                "part_name", "$1", "role", "(.*)"),
              "network_label", "Unnamed app: $1", "role", "(.*)")'';
        }

        # The share of the best peer's data held here, only while there is a
        # peer to compare with. +1 on both sides keeps an empty DHT defined.
        {
          record = "holochain:dht_share_raw";
          expr = ''
            clamp_max((holochain_dht_local_ops + 1) / (holochain_dht_peer_ops + 1), 1)
            and on (${dht}) (holochain_dht_peers > 0)'';
        }
        {
          record = "holochain:dht_share";
          expr = ''
            avg_over_time(holochain:dht_share_raw[${shareWindow}])
            and on (${dht}) (holochain_dht_peers > 0)'';
        }

        {
          record = "holochain:dht_had_peers";
          expr = "max_over_time(holochain_dht_peers[${historyWindow}]) > bool 0";
        }
        # Distinct nodes running each DNA: two apps sharing a DNA on one node
        # count once.
        {
          record = "holochain:dna_nodes";
          expr = "count by (dna) (count by (dna, node) (holochain_dht_peers))";
        }

        # The DHT state ladder.
        {
          record = "holochain:dht_state";
          expr = ''
              (holochain_dht_peers * 0 + 1)
                unless on (instance, conductor) (holochain:conductor_fresh == 1)
            or ((holochain_dht_peers == 0) * 0 + 2)
                and on (${dht}) (holochain:dht_had_peers == 1)
            or ((holochain_dht_peers == 0) * 0 + 2)
                and on (dna) (holochain:dna_nodes > 1)
            or ((holochain_dht_peers > 0) * 0 + 2)
                and on (${dht})
                  (holochain_dht_seconds_since_gossip > ${silent} or holochain_dht_seconds_since_gossip == -1)
            or ((holochain_dht_peers == 0) * 0 + 3)
            or ((holochain:dht_share < ${share}) * 0 + 4)
            or (holochain_dht_peers * 0 + 5)'';
        }

        # Named copies, for display. Counts that colour a panel read the
        # raw-keyed rules above, so a DHT whose name is missing still counts.
        {
          record = "holochain:dht_state:named";
          expr = named "holochain:dht_state";
        }
        {
          record = "holochain:dht_peers:named";
          expr = named "holochain_dht_peers";
        }
        {
          record = "holochain:dht_share:named";
          expr = named "holochain:dht_share";
        }
        # -1 (never) becomes 1e9, so max() and sorting take "never" as the
        # longest silence there is.
        {
          record = "holochain:dht_heard:named";
          expr = named "(holochain_dht_seconds_since_gossip >= 0) or (holochain_dht_seconds_since_gossip * 0 + 1e9)";
        }
        # Items the best peer has that this node does not have yet.
        {
          record = "holochain:dht_missing:named";
          expr = named "clamp_min(holochain_dht_peer_ops - holochain_dht_local_ops, 0)";
        }

        # An app's state is its worst DHT's. An app Holochain lists or Nix
        # expects, with no DHT series at all, reads 0 Not running; a disabled
        # one was switched off on purpose and is left out.
        {
          record = "holochain:app_state:named";
          expr = ''
              min by (instance, job, node, site, conductor, app_id, app_name, app_kind) (holochain:dht_state:named)
            or on (instance, conductor, app_id)
              0 * max by (instance, job, node, site, conductor, app_id, app_name, app_kind) (holochain_app_info{status!="disabled"})'';
        }

        {
          record = "holochain:conductor_state";
          expr = ''
              ((holochain_conductor_up == 0) * 0 + 1)
            or ((holochain:conductor_fresh == 0) * 0 + 2)
            or (holochain_conductor_up * 0 + 3)'';
        }

        # A node's state: unreachable wins over everything, then its worst
        # conductor, so one silent conductor cannot hide behind a healthy one.
        {
          record = "holochain:node_state";
          expr = ''
              (max by (instance, job, node, site) (up{job="holochain-nodes"}) == 0)
            or on (instance) min by (instance, job, node, site) (holochain:conductor_state)
            or on (instance) (max by (instance, job, node, site) (up{job="holochain-nodes"}) * 0 + 4)'';
        }

        # How close the fleet's nodes are to holding the same data of one DNA.
        # Assumes every node holds the whole DHT, which is true of a small
        # network without sharding.
        {
          record = "holochain:dna_same_data";
          expr = ''
            (min by (dna) (holochain_dht_local_ops) + 1) / (max by (dna) (holochain_dht_local_ops) + 1)
            and on (dna) (holochain:dna_nodes > 1)'';
        }

        # What a human must act on, one sentence each in the `problem` label.
        {
          record = "holochain:node_problem";
          expr = ''
              ${problem "A service has failed" ''max by (instance, node, site) (node_systemd_unit_state{state="failed"}) > 0''}
            or ${problem "A disk is over 90% full" "max by (instance, node, site) (1 - node_filesystem_avail_bytes{${virtualFs}} / node_filesystem_size_bytes{${virtualFs}}) > 0.9"}
            or ${problem "Memory is over 90% used" "max by (instance, node, site) (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.9"}
            or ${problem "Running hot (over 85 °C)" "max by (instance, node, site) (node_hwmon_temp_celsius) > 85"}
            or ${problem "A metrics file could not be read (see the node_exporter log)" "max by (instance, node, site) (node_textfile_scrape_error) > 0"}
            or label_replace(max by (instance, node, site, conductor) (holochain_conductor_up == 0),
                "problem", "Holochain ($1) is not answering", "conductor", "(.*)")
            or label_replace(max by (instance, node, site, conductor) (holochain:conductor_fresh == 0),
                "problem", "Holochain ($1) readings are over ${stale} s old", "conductor", "(.*)")
            or ${problem "Some app parts have no name yet" ''count by (instance, node, site) (holochain:dht_names{app_name="Unnamed app"}) > 0''}'';
        }
      ];
    }
  ];
}
