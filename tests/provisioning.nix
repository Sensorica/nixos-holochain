# What holochain-grafana renders from its options, read from evaluated
# systems with no VM: the node and site labels of every scrape target, the
# refusal of two targets that would go by one node name, the rule file and its
# states, and the dashboards as the module rewrites them on their way into the
# store (the units regex, the units' names as value mappings on the Service
# column, the room constants).
{
  pkgs,
  # A monitor node's config, from a list of extra modules.
  monitor,
}: let
  inherit (pkgs) lib;

  fixtures = ../tests/fixtures/dashboards;

  list = monitor [
    {
      services.holochain-grafana.scrapeTargets = ["127.0.0.1:9100" "edgenode-02:9100" "10.0.0.3:9100" "[fd00::7]:9100"];
    }
  ];
  # Two loopback ports in list form both take the host name.
  shared = monitor [
    {
      services.holochain-grafana.scrapeTargets = ["localhost:9100" "[::1]:9101"];
    }
  ];
  named = monitor [
    {
      services.holochain-grafana = {
        scrapeTargets = {
          lab-1 = {
            address = "edgenode-01:9100";
            site = "Sensorica lab";
          };
          homelab.address = "127.0.0.1:9100";
        };
        scrapeInterval = "20s";
        states = {
          inStepShare = 0.9;
          staleAfterSeconds = 120;
          shareWindow = "15m";
        };
        dashboards = fixtures;
        # A list and an attrset, both merged into the default.
        overviewUnits = lib.mkMerge [
          (lib.mkOptionDefault ["caddy.service"])
          (lib.mkOptionDefault {"restic-backups-.*" = "Backups";})
        ];
        room = {
          app = "requests-and-offers";
          part = "requests_and_offers";
          label = "Requests & Offers";
        };
      };
    }
  ];
  noRoom = monitor [{services.holochain-grafana.dashboards = fixtures;}];
  # A dashboards directory inside a package whose build always fails. Choosing
  # the home page must not build it, or a system whose dashboards come from a
  # package would not evaluate where import-from-derivation is off.
  unbuilt = monitor [
    {
      services.holochain-grafana.dashboards = "${pkgs.runCommand "dashboards-never-built" {} "exit 1"}/dashboards";
    }
  ];

  scrape = config: (lib.findFirst (c: c.job_name == "holochain-nodes") null config.services.prometheus.scrapeConfigs).static_configs;
  # This module's failed assertions; a bare evaluated system fails others
  # (no root file system, no boot loader) that say nothing here.
  # Only a failed assertion's message is read: some modules' messages cannot
  # be evaluated while their assertion holds.
  failed = config:
    lib.filter (lib.hasPrefix "services.holochain-grafana")
    (map (a: a.message) (lib.filter (a: !a.assertion) config.assertions));
  # This module's warnings.
  warned = config: lib.filter (lib.hasPrefix "services.holochain-grafana") config.warnings;
  dashboardsOf = config: (builtins.head config.services.grafana.provision.dashboards.settings.providers).options.path;
  homeOf = config: config.services.grafana.settings.dashboards.default_home_dashboard_path or null;

  facts = pkgs.writeText "provisioning-facts.json" (builtins.toJSON {
    list = {
      scrape = scrape list;
      failed = failed list;
      warnings = warned list;
      home = homeOf list;
      dashboards = dashboardsOf list;
    };
    shared.failed = failed shared;
    named = {
      scrape = scrape named;
      failed = failed named;
      warnings = warned named;
      units = named.services.holochain-grafana.overviewUnits;
      ruleFiles = map toString named.services.prometheus.ruleFiles;
      home = homeOf named;
      grafanaHome = "${named.services.grafana.package}/share/grafana/public/dashboards/home.json";
    };
    # Its string alone: with its context, this check would build the package.
    unbuilt.home = builtins.unsafeDiscardStringContext (homeOf unbuilt);
  });
in
  pkgs.runCommand "grafana-provisioning" {
    nativeBuildInputs = [pkgs.jq pkgs.yq-go];
  } ''
    jq . ${facts}
    check() {
      if ! jq -e "$1" ${facts} > /dev/null; then
        echo "not so: $1" >&2
        exit 1
      fi
    }

    # A list names each node after its host, a loopback after this machine.
    check '.list.scrape == [
      {targets: ["127.0.0.1:9100"], labels: {node: "monitor"}},
      {targets: ["edgenode-02:9100"], labels: {node: "edgenode-02"}},
      {targets: ["10.0.0.3:9100"], labels: {node: "10.0.0.3"}},
      {targets: ["[fd00::7]:9100"], labels: {node: "[fd00::7]"}}]'
    check '.list.failed == []'
    # A list entry given by an IP address goes by that address, and the
    # module says so; a host name and a loopback do not warn.
    check '.list.warnings | length == 2
      and (map(select(contains("\"10.0.0.3\""))) | length == 1)
      and (map(select(contains("\"[fd00::7]\""))) | length == 1)'
    # Two targets that would go by one name are refused, by that name.
    check '.shared.failed | length == 1 and (.[0] | contains("\"monitor\""))'
    # An attrset names each node by its key, with its site when given.
    check '.named.scrape | sort_by(.labels.node) == [
      {targets: ["127.0.0.1:9100"], labels: {node: "homelab"}},
      {targets: ["edgenode-01:9100"], labels: {node: "lab-1", site: "Sensorica lab"}}]'
    check '.named.failed == []'
    check '.named.warnings == []'
    # List and attrset definitions merge into the named default.
    check '.named.units["holochain-conductor.service"] == "Holochain conductor"
      and .named.units["caddy.service"] == null
      and .named.units["restic-backups-.*"] == "Backups"'

    # Grafana's home page is the shipped room screen, as provisioned (so with
    # its room constants); a dashboards directory without one gets a copy of
    # Grafana's own home page. Making that choice builds nothing while
    # evaluating: a package's directory that cannot be built still yields a
    # home path.
    cmp "$(jq -r .list.home ${facts})" "$(jq -r .list.dashboards ${facts})/holochain-now.json"
    jq -e '.uid == "holochain-now"' "$(jq -r .list.home ${facts})"
    cmp "$(jq -r .named.home ${facts})" "$(jq -r .named.grafanaHome ${facts})"
    check '.unbuilt.home | type == "string" and endswith("-holochain-grafana-home.json")'

    # The rule file: evaluated every scrape, with the states given.
    rules=$(jq -r '.named.ruleFiles[0]' ${facts})
    yq -o json "$rules" > rules.json
    jq -e '.groups | length == 1 and .[0].interval == "20s"' rules.json
    state() { jq -r --arg r "$1" '.groups[0].rules[] | select(.record == $r) | .expr' rules.json; }
    state holochain:dht_state | grep -qF 'holochain:dht_share < 0.9)'
    state holochain:dht_share | grep -qF 'holochain:dht_share_raw[15m]'
    state holochain:conductor_fresh | grep -qF '< bool 120'
    state holochain:node_problem | grep -qF 'readings are over 120 s old'
    state holochain:dht_had_peers | grep -qF '[24h]'

    # The dashboards as provisioned.
    d=${dashboardsOf named}/rewrite.json
    jq . "$d"
    dcheck() {
      if ! jq -e "$1" "$d" > /dev/null; then
        echo "not so in the provisioned dashboard: $1" >&2
        exit 1
      fi
    }
    dcheck '[.templating.list[] | select(.name == "units") | .current.value][0] | split("|") | index("caddy.service") != null and index("sshd.service") != null'
    dcheck '[.templating.list[] | {(.name): .query}] | add | .room_app == "requests-and-offers" and .room_part == "requests_and_offers" and .room_label == "Requests & Offers" and .room_app_note == "untouched" and .node == "label_values(up, node)"'
    dcheck '[.templating.list[] | select(.name == "room_label") | .current.text][0] == "Requests & Offers"'
    # Every Service column gets the units' names, and only them: the old
    # mapping is gone, its display name stays, and caddy, which has no
    # name, keeps its unit name.
    dcheck '[.. | objects | select(.matcher? == {id: "byName", options: "name"})] | length == 2'
    dcheck '[.. | objects | select(.matcher? == {id: "byName", options: "name"}) | [.properties[] | select(.id == "mappings")] | length] == [1, 1]'
    dcheck '.panels[0].fieldConfig.overrides[0].properties[0] == {id: "displayName", value: "Service"}'
    dcheck '[.. | objects | select(.matcher? == {id: "byName", options: "name"}) | .properties[] | select(.id == "mappings") | .value]
      | .[0] == .[1]
        and (.[0] | map(.options.result.text) | index("Holochain conductor") != null and index("Backups") != null and index("stale") == null)
        and (.[0] | map(select(.options.pattern == "^(?:restic-backups-.*)$" and .options.result.text == "Backups")) | length == 1)
        and (.[0] | map(select(.options.pattern | contains("caddy"))) | length == 0)
        and (.[0] | all(.type == "regex"))'
    # Other overrides are left as they were.
    dcheck '.panels[0].fieldConfig.overrides[1].properties == [{id: "mappings", value: [{type: "value", options: {failed: {text: "Failed", color: "red"}}}]}]'

    # With no room, the room constants keep the dashboard's own defaults.
    jq -e '[.templating.list[] | {(.name): .query}] | add | .room_app == "" and .room_label == "the room'"'"'s app"' ${dashboardsOf noRoom}/rewrite.json
    touch $out
  ''
