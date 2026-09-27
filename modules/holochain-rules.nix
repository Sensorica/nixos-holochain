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
#
#   Service (a watched unit, or a conductor no unit claims):
#     0 Failed              systemd says the unit failed
#     1 Stopped             the unit is inactive
#     2 Not answering       active, but its health check fails, or the
#                           conductor it runs does not answer
#     3 No fresh readings   active, and its health reading or its conductor's
#                           readings are older than staleAfterSeconds
#     4 Starting, 5 Stopping
#     6 Running
#
#   Node: 0 Unreachable, 1 Holochain not answering, 2 No fresh readings (a
#   conductor's or a service's), 3 A service is down (failed, stopped or not
#   answering), 4 Running, 5 No Holochain here: the worst of its conductors
#   and services, Unreachable over everything.
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
  # services.holochain-grafana.overviewUnits: a unit regex to the name a
  # person reads for it, or to null. Watched on every node that runs it, on
  # top of the units each node lists in holochain_service_info.
  unitNames ? {},
}: let
  num = builtins.toJSON;
  # A PromQL string literal, and a label_replace replacement that is taken as
  # it is (a `$` in it would otherwise refer to a capture).
  str = builtins.toJSON;
  literal = text: builtins.replaceStrings ["$"] ["$$"] text;

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

  # A conductor's problem, which says which conductor, except for one named
  # "Holochain" (conductorMetrics.name's default, so every single-conductor
  # node), which would read "Holochain (Holochain) ...".
  conductorProblem = text: expr: ''
    label_replace(
      label_replace(max by (instance, node, site, conductor) (${expr}),
        "problem", "Holochain ($1) ${text}", "conductor", "(.*)"),
      "problem", "Holochain ${text}", "conductor", "Holochain")'';

  # The overviewUnits keys, watched on every node that runs one: each unit
  # a key matches, named by its key's name, or by its unit name when the key
  # has none. label_replace anchors its regex, as Prometheus anchors `=~`, so
  # a key such as `restic-backups-.*` names every unit it matches.
  overviewKeys = builtins.attrNames unitNames;
  namedUnits = builtins.filter (unit: unitNames.${unit} != null) overviewKeys;
  overviewWatched =
    builtins.foldl' (expr: unit: ''
      label_replace(${expr},
        "service", ${str (literal unitNames.${unit})}, "name", ${str unit})'')
    ''
      label_replace(
        max by (instance, job, node, site, name) (node_systemd_unit_state{name=~${str (builtins.concatStringsSep "|" overviewKeys)}}) * 0 + 1,
        "service", "$1", "name", "(.*)")''
    namedUnits;

  # A service's state, when the watched unit is in a given systemd state or
  # a condition holds on the unit or on the conductor it runs.
  watched = "holochain:service_watched";
  unitIs = state: ''(node_systemd_unit_state{state="${state}"} == 1)'';
  serviceWhen = on: cond: code: "(${watched} and on (${on}) ${cond}) * 0 + ${toString code}";

  # One sentence per failed unit, watched or not: a failed unit the
  # dashboards do not watch is on no other panel. Named by its watched name,
  # else by its unit name.
  failedUnits = ''
    label_replace(
      (node_systemd_unit_state{state="failed"} > 0) * on (instance, name) group_left (service) ${watched},
      "problem", "$1 has failed", "service", "(.*)")
    or on (instance, name)
    label_replace(node_systemd_unit_state{state="failed"} > 0, "problem", "$1 has failed", "name", "(.*)")'';
  # A watched service that is down without having failed. Services that run a
  # conductor are left to the conductor's own sentences.
  serviceProblem = code: text: ''
    max by (instance, node, site, problem) (
      label_replace(holochain:service_state{conductor=""} == ${toString code}, "problem", "$1 ${text}", "service", "(.*)"))'';

  # The name of a part with no info row, from its role id, as the exporter
  # makes one (part_pretty in dht-metrics.jq): a one-letter prefix before a
  # capital goes ("rFiles" reads "Files"), runs of `_` and `-` become spaces
  # (up to six of them), and the first letter becomes a capital
  # ("requests_and_offers" reads "Requests and offers"). PromQL has no string
  # functions, so each step is a label_replace of the whole value.
  lower = "abcdefghijklmnopqrstuvwxyz";
  upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  onPart = expr: replacement: regex: ''label_replace(${expr}, "part_name", "${replacement}", "part_name", "${regex}")'';
  prettyPart = expr: let
    copied = ''label_replace(${expr}, "part_name", "$1", "role", "(.*)")'';
    unprefixed = onPart copied "$1" "[a-z]([A-Z].*)";
    spaced = builtins.foldl' (e: _: onPart e "$1 $2" "(.*?)[_-]+(.*)") unprefixed (builtins.genList (i: i) 6);
    trimmed = onPart spaced "$1" " *(.*?) *";
  in
    builtins.foldl' (e: i: onPart e "${builtins.substring i 1 upper}$1" "${builtins.substring i 1 lower}(.*)")
    trimmed (builtins.genList (i: i) 26);
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
        # row, so it is still drawn, as "Unnamed app" and a part named after
        # its role, and still counted. Two such apps that share a role read
        # alike: no label may carry the app id, and the problem "Some app
        # parts have no name yet" asks for the names.
        {
          record = "holochain:dht_names";
          expr = ''
            holochain_dht_info
            or on (${dht})
            label_replace(
              ${prettyPart ''label_replace(holochain_dht_peers * 0 + 1, "app_name", "Unnamed app", "", "")''},
              "network_label", "Unnamed app: $1", "part_name", "(.*)")'';
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

        # The history is kept per full key, so it starts afresh when the key
        # of a DHT's series changes, as at the switch from an exporter that
        # wrote other labels. For up to historyWindow after such a change, a
        # DHT that lost its peers before it reads No one else yet rather than
        # Lost contact, unless another node of the fleet runs its DNA.
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

        # The services watched on each node: the ones it lists itself, from
        # the modules enabled on it, and the overviewUnits the monitor adds.
        # One series per unit and node, its name in `service`, and for a unit
        # that runs a conductor, that conductor in `conductor`.
        {
          record = watched;
          expr =
            if overviewKeys == []
            then "holochain_service_info"
            else ''
              holochain_service_info
              or on (instance, name)
              ${overviewWatched}'';
        }

        # The service ladder: the first branch that matches wins. The unit's
        # own state first, then whether it answers, then whether anyone has
        # looked lately. A conductor that no watched unit claims (a Moss node
        # run by another program) is a service of its own, "<conductor> node".
        {
          record = "holochain:service_state";
          expr = ''
              ${serviceWhen "instance, name" (unitIs "failed") 0}
            or ${serviceWhen "instance, name" (unitIs "inactive") 1}
            or ${serviceWhen "instance, name" (unitIs "activating") 4}
            or ${serviceWhen "instance, name" (unitIs "deactivating") 5}
            or ${serviceWhen "instance, name" "(holochain_service_healthy == 0)" 2}
            or ${serviceWhen "instance, conductor" "(holochain:conductor_state == 1)" 2}
            or ${serviceWhen "instance, name" "((time() - holochain_service_health_timestamp_seconds) > ${stale})" 3}
            or ${serviceWhen "instance, conductor" "(holochain:conductor_state == 2)" 3}
            or ${serviceWhen "instance, name" (unitIs "active") 6}
            or label_replace(
                 (   (holochain:conductor_state == 1) * 0 + 2
                  or (holochain:conductor_state == 2) * 0 + 3
                  or (holochain:conductor_state == 3) * 0 + 6)
                 unless on (instance, conductor) ${watched},
                 "service", "$1 node", "conductor", "(.+)")'';
        }

        # A node's state: unreachable wins over everything, then the worst of
        # its conductors and services, so one silent conductor or stopped
        # service cannot hide behind healthy ones. A conductor's own codes are
        # the node's, but Running, which moves up one for A service is down.
        {
          record = "holochain:node_state";
          expr = ''
              (max by (instance, job, node, site) (up{job="holochain-nodes"}) == 0)
            or on (instance) min by (instance, job, node, site) (
                 (holochain:conductor_state < 3)
              or (holochain:conductor_state == 3) + 1
              or (holochain:service_state == 3) * 0 + 2
              or (holochain:service_state <= 2) * 0 + 3)
            or on (instance) (max by (instance, job, node, site) (up{job="holochain-nodes"}) * 0 + 5)'';
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
              max by (instance, node, site, problem) (${failedUnits})
            or ${serviceProblem 1 "is stopped"}
            or ${serviceProblem 2 "is not answering"}
            or ${problem "A disk is over 90% full" "max by (instance, node, site) (1 - node_filesystem_avail_bytes{${virtualFs}} / node_filesystem_size_bytes{${virtualFs}}) > 0.9"}
            or ${problem "Memory is over 90% used" "max by (instance, node, site) (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.9"}
            or ${problem "Running hot (over 85 °C)" "max by (instance, node, site) (node_hwmon_temp_celsius) > 85"}
            or ${problem "A metrics file could not be read (see the node_exporter log)" "max by (instance, node, site) (node_textfile_scrape_error) > 0"}
            or ${conductorProblem "is not answering" "holochain_conductor_up == 0"}
            or ${conductorProblem "readings are over ${stale} s old" "holochain:conductor_fresh == 0"}
            or ${problem "Some app parts have no name yet" ''count by (instance, node, site) (holochain:dht_names{app_name="Unnamed app"}) > 0''}'';
        }
      ];
    }
  ];
}
