# What holochain-grafana renders from its options, read from evaluated
# systems with no VM: the node and site labels of every scrape target, the
# refusal of two targets that would go by one node name, the rule file and its
# states, and the dashboards as the module rewrites them on their way into the
# store (the units regex, the units' names as value mappings on the Service
# column, the room constants). Also the services each machine lists for the
# dashboards, from the modules enabled on it.
{
  pkgs,
  # A monitor node's config, from a list of extra modules.
  monitor,
  # The other modules, to evaluate a machine that runs every one of them.
  modules,
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
  # The shipped dashboards under states other than every default, as a fleet
  # recalibrated at the event would set them.
  restated = monitor [
    {
      services.holochain-grafana.states = {
        staleAfterSeconds = 120;
        silentAfterSeconds = 900;
        inStepShare = 0.8;
        shareWindow = "15m";
        historyWindow = "2d";
      };
    }
  ];

  # A monitor that runs every module that installs a service, with sshd and
  # Tailscale beside them, and the same machine without the bootstrap server.
  # What each lists for the dashboards must follow what is enabled on it.
  everything = bootstrap:
    monitor [
      modules.edgenode
      modules.holochain-http-gateway
      modules.holochain-bootstrap
      modules.holochain-windtunnel
      {
        services.holochain-edgenode = {
          enable = true;
          metricsExporter = {
            enable = true;
            textfileDirectory = "/var/lib/holochain-textfiles";
          };
          conductorMetrics = {
            enable = true;
            name = "Workshop";
          };
        };
        services.holochain-http-gateway.enable = true;
        services.holochain-bootstrap.enable = bootstrap;
        services.holochain-windtunnel.enable = true;
        services.openssh.enable = true;
        services.tailscale.enable = true;
      }
    ];
  withBootstrap = everything true;
  withoutBootstrap = everything false;
  servicesOf = config: {
    inherit (config.services.holochain-services) units healthChecks textfileDirectory;
    # The health timer, when there is one to run.
    healthTimer = config.systemd.timers ? holochain-service-health;
    flags = config.services.prometheus.exporters.node.extraFlags;
  };

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
    services = {
      monitor = servicesOf list;
      withBootstrap = servicesOf withBootstrap;
      withoutBootstrap = servicesOf withoutBootstrap;
    };
    restated.dashboards = dashboardsOf restated;
  });
  shipped = ../modules/dashboards;
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
    # List and attrset definitions merge into the default, which is empty:
    # what is watched follows each node's own configuration.
    check '.named.units == {"caddy.service": null, "restic-backups-.*": "Backups"}'

    # Every machine lists the services of the modules enabled on it, and only
    # those, by name. A monitor alone: its own, in the textfile directory its
    # node_exporter reads.
    check '.services.monitor.units | map_values(.name) == {
      "prometheus.service": "Metrics database", "grafana.service": "Dashboards",
      "prometheus-node-exporter.service": "Machine readings", "nix-daemon.socket": "Nix"}'
    check '.services.monitor.textfileDirectory == "/var/lib/prometheus-node-exporter-text-files"
      and (.services.monitor.flags | index("--collector.textfile.directory=/var/lib/prometheus-node-exporter-text-files") != null)
      and .services.monitor.healthTimer == false'
    # Every module at once: each adds its units, the conductor claims its
    # readings' conductor, and the bootstrap server gets a health check on the
    # address it listens on.
    check '.services.withBootstrap.units | map_values(.name) == {
      "holochain-conductor.service": "Holochain conductor",
      "holochain-conductor-metrics.timer": "Holochain readings (timer)",
      "holochain-http-gateway.service": "HTTP gateway",
      "holochain-bootstrap.service": "Local bootstrap and relay",
      "podman-wind-tunnel-runner.service": "Wind Tunnel runner",
      "prometheus.service": "Metrics database", "grafana.service": "Dashboards",
      "prometheus-node-exporter.service": "Machine readings", "nix-daemon.socket": "Nix",
      "sshd.service": "Remote login", "tailscaled.service": "Private network (Tailscale)"}'
    check '.services.withBootstrap.units["holochain-conductor.service"].conductor == "Workshop"
      and ([.services.withBootstrap.units[] | select(.conductor != null)] | length == 1)'
    check '.services.withBootstrap.healthChecks == {"holochain-bootstrap.service": {url: "http://127.0.0.1:443/health", insecure: false, timeoutSeconds: 5}}
      and .services.withBootstrap.healthTimer == true'
    # The edgenode's own textfile directory wins over the monitor default.
    check '.services.withBootstrap.textfileDirectory == "/var/lib/holochain-textfiles"'
    # Without the bootstrap server, nothing of it is listed or checked.
    check '(.services.withoutBootstrap.units | has("holochain-bootstrap.service") | not)
      and (.services.withoutBootstrap.units | has("holochain-http-gateway.service"))
      and .services.withoutBootstrap.healthChecks == {} and .services.withoutBootstrap.healthTimer == false'

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
    dcheck '[.templating.list[] | select(.name == "units") | .current.value][0] | split("|") | sort == ["caddy.service", "restic-backups-.*"]'
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
        and (.[0] | map(.options.result.text) == ["Backups"])
        and (.[0] | map(select(.options.pattern == "^(?:restic-backups-.*)$" and .options.result.text == "Backups")) | length == 1)
        and (.[0] | map(select(.options.pattern | contains("caddy"))) | length == 0)
        and (.[0] | all(.type == "regex"))'
    # Other overrides are left as they were.
    dcheck '.panels[0].fieldConfig.overrides[1].properties == [{id: "mappings", value: [{type: "value", options: {failed: {text: "Failed", color: "red"}}}]}]'

    # With no room, the room constants keep the dashboard's own defaults.
    jq -e '[.templating.list[] | {(.name): .query}] | add | .room_app == "" and .room_label == "the room'"'"'s app"' ${dashboardsOf noRoom}/rewrite.json

    # The state thresholds on the shipped dashboards. With the default states
    # the steps and the sentences are the shipped ones; with others, every
    # step that names a state takes its value, the plain steps beside it keep
    # their order, and no sentence still quotes a default.
    texts='[.. | objects | (.description?, .options?.content?, .steps?) | select(. != null)]'
    for f in ${shipped}/*.json; do
      name=$(basename "$f")
      if ! cmp -s <(jq "$texts" "$f") <(jq "$texts" "$(jq -r .list.dashboards ${facts})/$name"); then
        echo "the default states changed a step or a sentence of $name" >&2
        exit 1
      fi
    done
    restated=$(jq -r .restated.dashboards ${facts})
    jq -s '[.[] | .. | objects | select(has("fromOption"))]' "$restated"/*.json > marked.json
    jq -c 'group_by(.fromOption) | map({(.[0].fromOption): map(.value) | unique}) | add' marked.json
    jq -e 'length == 9 and (group_by(.fromOption) | map({(.[0].fromOption): map(.value) | unique}) | add)
      == {staleAfterSeconds: [120], silentAfterSeconds: [900], inStepShare: [0.8]}' marked.json
    steps() { jq -c --arg t "$2" '[.. | objects | select(.title? == $t)] | first | [.. | objects | select(has("steps")) | .steps | map(.value)]' "$restated/$1"; }
    steps holochain-node.json "Readings" | tee /dev/stderr | grep -qxF '[[null,120,300]]'
    steps holochain-node.json "Share held, per part" | tee /dev/stderr | grep -qxF '[[null,0.8,0.8]]'
    steps holochain-now.json "Last heard from others, per app" | tee /dev/stderr | grep -qxF '[[null,120,900]]'
    steps holochain-network.json "Same data everywhere" | tee /dev/stderr | grep -qxF '[[null,0.8,0.95]]'
    for old in "more than 90 seconds old" "in 90 s" "at 600 s" "95%" "10 minutes" "24 hours"; do
      if grep -lF -- "$old" "$restated"/*.json; then
        echo "a sentence still quotes \"$old\"" >&2
        exit 1
      fi
    done
    for new in "more than 2 minutes old" "in 120 s" "at 900 s" "heard from them for 15 minutes" "under 80%" \
      "less than 80%" "at least 80%" "averaged over 15 minutes" "over the last 15 minutes" "in the last 2 days"; do
      grep -qF -- "$new" "$restated"/*.json || { echo "no sentence says \"$new\"" >&2; exit 1; }
    done
    touch $out
  ''
