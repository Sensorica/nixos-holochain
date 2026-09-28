# What holochain-grafana renders from its options, read from evaluated
# systems with no VM: the node and site labels of every scrape target, the
# refusal of two targets that would go by one node name, the rule file and its
# states, and the dashboards as the module rewrites them on their way into the
# store (the units regex, the units' names as value mappings on the Service
# column, the room constants). Also the services each machine lists for the
# dashboards, from the modules enabled on it, each with the version of the
# package it runs, and Grafana's home page: "What is this machine running?",
# opening on this machine's own node.
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
      services.holochain-grafana.scrapeTargets = ["127.0.0.1:9100" "sensorica-holoport-02:9100" "10.0.0.3:9100" "[fd00::7]:9100"];
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
            address = "sensorica-holoport-01:9100";
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
  shipped = ../modules/dashboards;
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
  # A Moss node beside the edgenode: its unit carries wdocker's version and
  # the Holochain that wdocker brings, which is not the edgenode's.
  withMoss = monitor [
    modules.edgenode
    modules.holochain-moss-node
    {
      services.holochain-edgenode = {
        enable = true;
        metricsExporter.enable = true;
        conductorMetrics.enable = true;
      };
      services.holochain-moss-node = {
        enable = true;
        passwordFile = "/var/lib/secrets/moss-node-password";
      };
    }
  ];

  # The home page as each kind of target list provisions it: a list names a
  # loopback target after this machine, an attrset by its key, and a list with
  # no loopback leaves this machine's host name.
  homeNamed = monitor [
    {
      services.holochain-grafana.scrapeTargets = {
        lab-1.address = "sensorica-holoport-01:9100";
        homelab.address = "127.0.0.1:9100";
      };
    }
  ];
  homeRemote = monitor [
    {
      services.holochain-grafana.scrapeTargets = ["sensorica-holoport-02:9100" "monitor:9100"];
    }
  ];
  # Broken copies of the shipped dashboards: one without the home page, whose
  # home falls back to the room screen, and one whose home page lost its uid.
  # The home page check must refuse both.
  withoutHome = monitor [
    {
      services.holochain-grafana.dashboards = "${pkgs.runCommand "dashboards-without-home" {} ''
        cp -r ${shipped} $out
        chmod -R u+w $out
        rm $out/holochain-home.json
      ''}";
    }
  ];
  homeRenamed = monitor [
    {
      services.holochain-grafana.dashboards = "${pkgs.runCommand "dashboards-home-renamed" {nativeBuildInputs = [pkgs.jq];} ''
        cp -r ${shipped} $out
        chmod -R u+w $out
        jq '.uid = "somewhere-else"' ${shipped}/holochain-home.json > $out/holochain-home.json
      ''}";
    }
  ];
  # sshd started from its socket, which defines no sshd.service; and a unit
  # listed that nothing defines, which would have no row on the pages.
  socketSsh = monitor [
    {
      services.openssh = {
        enable = true;
        startWhenNeeded = true;
      };
    }
  ];
  ghost = monitor [{services.holochain-services.units."ghost.service" = "Ghost";}];
  servicesOf = config: {
    inherit (config.services.holochain-services) units healthChecks textfileDirectory;
    # The file node_exporter publishes the list from, as the machine links it.
    file = let
      rule = lib.findFirst (lib.hasInfix "/holochain-services.prom ") null config.systemd.tmpfiles.rules;
    in
      if rule == null
      then null
      else lib.last (lib.splitString " " rule);
    # The health timer, when there is one to run.
    healthTimer = config.systemd.timers ? holochain-service-health;
    flags = config.services.prometheus.exporters.node.extraFlags;
    warnings = lib.filter (lib.hasPrefix "services.holochain-services") config.warnings;
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
      socketSsh = servicesOf socketSsh;
      ghost = servicesOf ghost;
    };
    restated.dashboards = dashboardsOf restated;
    # The versions each module should publish, from the packages it runs.
    packages = let
      c = withBootstrap.services;
    in {
      conductor = lib.getVersion c.holochain-edgenode.package;
      hc = lib.getVersion c.holochain-edgenode.hcPackage;
      gateway = lib.getVersion c.holochain-http-gateway.package;
      bootstrap = lib.getVersion c.holochain-bootstrap.package;
      prometheus = lib.getVersion c.prometheus.package;
      grafana = lib.getVersion c.grafana.package;
      # The monitors are built from the same nixpkgs as pkgs.
      nodeExporter = lib.getVersion pkgs.prometheus-node-exporter;
      openssh = lib.getVersion c.openssh.package;
      tailscale = lib.getVersion c.tailscale.package;
      nix = lib.getVersion withBootstrap.nix.package;
      moss = lib.getVersion withMoss.services.holochain-moss-node.package;
      mossHolochain = withMoss.services.holochain-moss-node.package.holochainVersion;
    };
    moss = servicesOf withMoss;
    homes = {
      named = {
        home = homeOf homeNamed;
        dashboards = dashboardsOf homeNamed;
      };
      remote = {
        home = homeOf homeRemote;
        dashboards = dashboardsOf homeRemote;
      };
      withoutHome = {
        home = homeOf withoutHome;
        dashboards = dashboardsOf withoutHome;
      };
      renamed = {
        home = homeOf homeRenamed;
        dashboards = dashboardsOf homeRenamed;
      };
    };
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
      {targets: ["sensorica-holoport-02:9100"], labels: {node: "sensorica-holoport-02"}},
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
      {targets: ["sensorica-holoport-01:9100"], labels: {node: "lab-1", site: "Sensorica lab"}}]'
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
      "holochain-conductor.service": "Holochain conductor (Workshop)",
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
    # node_exporter counts restarts on every machine, so a service that keeps
    # failing while systemd restarts it reads Failed, not Starting.
    check 'all(.services.monitor, .services.withBootstrap; .flags | index("--collector.systemd.enable-restarts-metrics") != null)'
    # Every unit the modules list is one the configuration defines, so none
    # is warned about; sshd started from its socket is listed as the socket.
    check 'all(.services.monitor, .services.withBootstrap, .services.withoutBootstrap, .services.socketSsh; .warnings == [])'
    check '(.services.socketSsh.units | has("sshd.socket")) and (.services.socketSsh.units | has("sshd.service") | not)
      and .services.socketSsh.units["sshd.socket"].name == "Remote login"'
    check '.services.withBootstrap.units | has("sshd.service")'
    # A unit listed that nothing defines is warned about by name.
    check '.services.ghost.warnings | length == 1 and (.[0] | contains("\"ghost.service\""))'

    # Every unit a module declares carries the version of the package it
    # runs it from, except the two readings timers and the Wind Tunnel
    # runner, whose container is pulled by digest; the conductor also
    # carries the Holochain it is.
    check '.packages as $p | .services.withBootstrap.units | map_values(.version) == {
      "holochain-conductor.service": $p.conductor, "holochain-conductor-metrics.timer": "",
      "holochain-http-gateway.service": $p.gateway, "holochain-bootstrap.service": $p.bootstrap,
      "podman-wind-tunnel-runner.service": "",
      "prometheus.service": $p.prometheus, "grafana.service": $p.grafana,
      "prometheus-node-exporter.service": $p.nodeExporter, "nix-daemon.socket": $p.nix,
      "sshd.service": $p.openssh, "tailscaled.service": $p.tailscale}'
    check '[.packages[] | test("^[0-9]+[.][0-9]+")] | all'
    check '.services.withBootstrap.units["holochain-conductor.service"].holochainVersion == .packages.conductor
      and ([.services.withBootstrap.units[] | select(.holochainVersion != "")] | length == 1)'
    # The Moss node: wdocker's version, and the Holochain wdocker brings,
    # which is not the edgenode's; its readings timer has none.
    check '.moss.units["moss-node.service"] == {name: "Moss node", conductor: "Moss", version: .packages.moss, holochainVersion: .packages.mossHolochain}
      and .moss.units["moss-node-metrics.timer"].version == ""
      and .moss.units["holochain-conductor.service"].holochainVersion != .packages.mossHolochain'

    # The file each machine publishes its list from names every unit it
    # lists, and each unit that declares a version with that version, as the
    # version label. Checked on the file the module links, then on a copy
    # with one label gone, which must fail by that unit's name.
    versioned() {
      local file=$1 config=$2
      [ "$(grep -c '^holochain_service_info{' "$file")" = "$(jq --arg c "$config" '.[$c].units | length' units.json)" ] \
        || { echo "$file does not list every unit of $config" >&2; return 1; }
      jq -r --arg c "$config" '.[$c].units | to_entries[] | select(.value.version != "")
          | "\(.key)\t\(.value.version)\t\(.value.holochainVersion)"' units.json \
        | while IFS=$'\t' read -r unit version holochain; do
            line=$(grep -F "name=\"$unit\"" "$file" || true)
            case "$line" in *",version=\"$version\""*) ;; *) echo "$unit has lost its version label" >&2; exit 1 ;; esac
            if [ -n "$holochain" ]; then
              case "$line" in *"holochain_version=\"$holochain\""*) ;; *) echo "$unit has lost its holochain_version label" >&2; exit 1 ;; esac
            fi
          done
    }
    jq '.services + {moss: .moss}' ${facts} > units.json
    for config in withBootstrap moss; do
      file=$(jq -r --arg c "$config" '.[$c].file' units.json)
      cat "$file"
      versioned "$file" "$config"
    done
    broken_versions() {
      local reason=$1 config=$2 edit=$3
      sed "$edit" "$(jq -r --arg c "$config" '.[$c].file' units.json)" > broken.prom
      if versioned broken.prom "$config" 2> broken.log; then
        echo "still passes with $reason" >&2
        exit 1
      fi
      grep -qF "$reason" broken.log || { echo "failed, but not for $reason:" >&2; cat broken.log >&2; exit 1; }
      echo "fails as it should: $reason"
    }
    broken_versions "holochain-conductor.service has lost its version label" withBootstrap \
      '/name="holochain-conductor.service"/s/,version="[^"]*"//'
    broken_versions "grafana.service has lost its version label" withBootstrap \
      '/name="grafana.service"/s/,version="[^"]*"//'
    broken_versions "moss-node.service has lost its holochain_version label" moss \
      '/name="moss-node.service"/s/holochain_version="[^"]*",//'

    # Grafana's home page is "What is this machine running?" as provisioned,
    # so with its node set to this machine. A dashboards directory without it
    # falls back to the room screen, and one with neither gets a copy of
    # Grafana's own home page. Making that choice builds nothing while
    # evaluating: a package's directory that cannot be built still yields a
    # home path.
    is_home() {
      local home=$1 dashboards=$2
      cmp -s "$home" "$dashboards/holochain-home.json" && jq -e '.uid == "holochain-home"' "$home" > /dev/null
    }
    home_node() { jq -r '.templating.list[] | select(.name == "node") | .current.value' "$1"; }
    for kind in list homes.named homes.remote; do
      home=$(jq -r ".$kind.home" ${facts})
      is_home "$home" "$(jq -r ".$kind.dashboards" ${facts})" || { echo "the $kind monitor's home page is not the provisioned home page" >&2; exit 1; }
    done
    # It opens on this machine: a loopback target's name, or the host name.
    test "$(home_node "$(jq -r .list.home ${facts})")" = monitor
    test "$(home_node "$(jq -r .homes.named.home ${facts})")" = homelab
    test "$(home_node "$(jq -r .homes.remote.home ${facts})")" = monitor
    # The other pages keep their own node default.
    test "$(jq -c '.templating.list[] | select(.name == "node") | .current' "$(jq -r .list.dashboards ${facts})/holochain-node.json")" = '{}'
    # The broken copies: each must be refused.
    for kind in withoutHome renamed; do
      if is_home "$(jq -r ".homes.$kind.home" ${facts})" "$(jq -r ".homes.$kind.dashboards" ${facts})"; then
        echo "the home page check passes on the $kind copy" >&2
        exit 1
      fi
      echo "fails as it should: the $kind copy is not the home page"
    done
    # Without the home page, the room screen; with neither, Grafana's own.
    cmp "$(jq -r .homes.withoutHome.home ${facts})" "$(jq -r .homes.withoutHome.dashboards ${facts})/holochain-now.json"
    jq -e '.uid == "holochain-now"' "$(jq -r .homes.withoutHome.home ${facts})"
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
