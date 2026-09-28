# modules/holochain-grafana.nix
#
# Prometheus + Grafana observability module for a Holochain fleet.
# Enable on the designated monitor node; all peer nodes should set
#   services.holochain-edgenode.metricsExporter.enable = true;
#   services.holochain-edgenode.conductorMetrics.enable = true;
# the first gives the host series, the second the holochain_* series the
# provisioned dashboard is built around. Prometheus names each node from
# scrapeTargets and computes every state the dashboards show once, in the
# recording rules of holochain-rules.nix.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.holochain-grafana;

  # A dashboard's variable defaults and value mappings live in its JSON, and
  # the JSON reaches Grafana read-only, so the only way a module option can set
  # one is by rewriting the file on its way into the store. In every
  # provisioned dashboard:
  #
  #   * a textbox variable named `units` gets the overviewUnits regex as its
  #     default;
  #   * a field override matched by name to `name` (the unit label of
  #     node_systemd_unit_state) gets the overviewUnits names as its value
  #     mappings, replacing any it had;
  #   * constant variables named `room_app`, `room_part` and `room_label` get
  #     the `room` option's values, when it is set;
  #   * a threshold step that names a `states` option in `fromOption` takes
  #     that option's value, and the plain steps beside it move with it so
  #     the steps stay in order, so a colour changes where the state word
  #     the rules compute changes;
  #   * the sentences that quote a state's threshold ("more than 90 seconds
  #     old", "at least 95%") quote the value given instead.
  #
  # Everything else in the directory is copied unchanged. A directory outside
  # the store is read by Grafana at runtime and cannot be rewritten here, so it
  # is passed through as it is.
  #
  # "In the store" means a path literal, or a string that points into the
  # store and carries the context that makes it a build input, such as
  # "''${inputs.x}/dashboards". lib.isStorePath alone would miss the second:
  # it is true only for a top-level store path, not for a directory inside one.
  unitsRegex = lib.concatStringsSep "|" (lib.attrNames cfg.overviewUnits);
  # One regex mapping per named unit, anchored the way Prometheus anchors the
  # `units` match, so an entry that is a regex names every unit it matches.
  namedUnits = lib.filter (unit: cfg.overviewUnits.${unit} != null) (lib.attrNames cfg.overviewUnits);
  unitMappings = builtins.toJSON (lib.imap0 (index: unit: {
      type = "regex";
      options = {
        pattern = "^(?:${unit})$";
        result = {
          text = cfg.overviewUnits.${unit};
          inherit index;
        };
      };
    })
    namedUnits);
  roomJson = builtins.toJSON cfg.room;
  statesJson = builtins.toJSON cfg.states;
  dashboardsPath = toString cfg.dashboards;
  dashboardsInStore =
    builtins.isPath cfg.dashboards
    || (lib.hasPrefix "${builtins.storeDir}/" dashboardsPath && builtins.hasContext dashboardsPath);
  provisionedDashboards =
    if dashboardsInStore
    then
      pkgs.runCommand "holochain-grafana-dashboards" {
        nativeBuildInputs = [pkgs.jq];
        inherit unitsRegex unitMappings roomJson statesJson;
      } ''
        cp -rL --no-preserve=mode ${cfg.dashboards} $out
        find $out -type f -name '*.json' | while IFS= read -r f; do
          jq --arg units "$unitsRegex" --argjson mappings "$unitMappings" --argjson room "$roomJson" \
            --argjson states "$statesJson" '
            def default($v): .query = $v
              | .current = {text: $v, value: $v}
              | .options = [{selected: true, text: $v, value: $v}];
            def variable:
              if .type == "textbox" and .name == "units" then default($units)
              elif $room == null or .type != "constant" then .
              elif .name == "room_app" then default($room.app)
              elif .name == "room_part" then default($room.part)
              elif .name == "room_label" then default($room.label)
              else .
              end;
            def unitNames:
              if .matcher == {id: "byName", options: "name"}
              then .properties = [(.properties // [])[] | select(.id != "mappings")]
                + [{id: "mappings", value: $mappings}]
              else .
              end;
            # Steps that come from a state, and the plain steps around them
            # clamped between them, so the colours keep their order.
            def restateSteps:
              if (.steps | type) == "array" and any(.steps[]; type == "object" and has("fromOption"))
              then .steps |= (map(if type == "object" and has("fromOption") then .value = $states[.fromOption] else . end)
                | . as $s
                | [range(length) as $i | $s[$i]
                   | if has("fromOption") or .value == null then .
                     else ([$s[:$i][] | select(has("fromOption")) | .value] | max) as $lo
                       | ([$s[$i + 1:][] | select(has("fromOption")) | .value] | min) as $hi
                       | .value |= (if $lo != null and . < $lo then $lo else . end
                           | if $hi != null and . > $hi then $hi else . end)
                     end])
              else .
              end;
            def plural($n; $unit): "\($n) \($unit)\(if $n == 1 then "" else "s" end)";
            def seconds:
              if . >= 3600 and . % 3600 == 0 then plural(. / 3600; "hour")
              elif . >= 60 and . % 60 == 0 then plural(. / 60; "minute")
              else plural(.; "second")
              end;
            def duration: capture("^(?<n>[0-9]+)(?<u>ms|s|m|h|d|w|y)$")
              | plural(.n | tonumber; {ms: "millisecond", s: "second", m: "minute", h: "hour", d: "day", w: "week", y: "year"}[.u]);
            def percent: "\((. * 1000 | round) / 10)%";
            # Every sentence that quotes a state threshold, as the shipped
            # dashboards word it with the default states, and as it reads
            # with the states given. With the defaults each reads the same.
            def sentences: [
              ["more than 90 seconds old", "more than \($states.staleAfterSeconds | seconds) old"],
              ["in 90 s", "in \($states.staleAfterSeconds) s"],
              ["at 600 s", "at \($states.silentAfterSeconds) s"],
              ["heard from them for 10 minutes", "heard from them for \($states.silentAfterSeconds | seconds)"],
              ["under 95%", "under \($states.inStepShare | percent)"],
              ["less than 95%", "less than \($states.inStepShare | percent)"],
              ["at least 95%", "at least \($states.inStepShare | percent)"],
              ["averaged over 10 minutes", "averaged over \($states.shareWindow | duration)"],
              ["over the last 10 minutes", "over the last \($states.shareWindow | duration)"],
              ["in the last 24 hours", "in the last \($states.historyWindow | duration)"]
            ];
            def restated: reduce sentences[] as [$old, $new] (.; split($old) | join($new));
            if type == "object" and has("panels")
            then (.templating.list // empty) |= map(variable)
              | (.. | objects | select(has("fieldConfig")) | .fieldConfig.overrides // empty) |= map(unitNames)
              | walk(if type == "object" then restateSteps elif type == "string" then restated else . end)
            else .
            end
          ' "$f" > "$f.tmp"
          mv "$f.tmp" "$f"
        done
      ''
    else cfg.dashboards;

  # Grafana's home page is the room screen, copied from the provisioned
  # dashboards so it carries the room constants. Grafana answers a home path
  # that does not exist with an error, so a directory without the room screen
  # gets a copy of Grafana's own home page instead. The choice is made while
  # building, not by looking into the directory while evaluating: a directory
  # inside a package would otherwise be built during evaluation, which fails
  # where import-from-derivation is disabled.
  homeDashboard =
    pkgs.runCommand "holochain-grafana-home.json" {
      grafanaHome = "${config.services.grafana.package}/share/grafana/public/dashboards/home.json";
    } ''
      if [ -e ${provisionedDashboards}/holochain-now.json ]; then
        cp ${provisionedDashboards}/holochain-now.json $out
      else
        cp "$grafanaHome" $out
      fi
    '';

  # The dashboard JSON refers to its data source by this uid rather than by
  # name, so the file stays valid whatever the datasource is called.
  datasourceUid = "holochain-prometheus";

  generatedSecretKey = "${config.services.grafana.dataDir}/secret_key";

  # Files the operator supplies reach Grafana as systemd credentials, so they
  # need no grafana ownership and may exist before the grafana user does.
  credential = name: "$__file{/run/credentials/grafana.service/${name}}";
  secretKeyPath =
    if cfg.secretKeyFile != null
    then credential "secret_key"
    else "$__file{${generatedSecretKey}}";

  # Every scrape target with the name its node goes by on the dashboards.
  # Prometheus attaches `node` (and `site`, when given) to every series it
  # scrapes from the target, so a node that is down still has its name.
  loopback = ["127.0.0.1" "localhost" "::1" "[::1]"];
  nodeOf = address: let
    hostPort = builtins.match "(.*):[0-9]+" address;
    host =
      if hostPort == null
      then address
      else builtins.head hostPort;
  in
    if builtins.elem host loopback
    then config.networking.hostName
    else host;
  targets =
    if builtins.isList cfg.scrapeTargets
    then
      map (address: {
        inherit address;
        node = nodeOf address;
        site = null;
      })
      cfg.scrapeTargets
    else
      lib.mapAttrsToList (node: target: {
        inherit node;
        inherit (target) address site;
      })
      cfg.scrapeTargets;
  # List targets given by an IP address, which then goes by that address.
  addressNamed = lib.optionals (builtins.isList cfg.scrapeTargets) (lib.filter (target: builtins.match "[0-9.]+|\\[.*]|.*:.*" target.node != null) targets);
  nodeNames = map (target: target.node) targets;
  sharedNodeNames = lib.filter (name: lib.count (n: n == name) nodeNames > 1) (lib.unique nodeNames);

  # The recording rules the dashboards read (holochain-rules.nix), evaluated
  # as often as Prometheus scrapes.
  rulesFile = (pkgs.formats.yaml {}).generate "holochain-rules.yml" (import ./holochain-rules.nix {
    interval = cfg.scrapeInterval;
    inherit (cfg) states;
    unitNames = cfg.overviewUnits;
  });

  # Where a monitor that is not an edgenode lets node_exporter read textfiles,
  # so its own services (Prometheus, Grafana) reach the dashboards too. An
  # edgenode's own setting replaces this one.
  defaultTextfileDirectory = "/var/lib/prometheus-node-exporter-text-files";
  edgenodeExports = (config.services.holochain-edgenode.enable or false) && (config.services.holochain-edgenode.metricsExporter.enable or false);
in {
  # The services this node runs, by name, for the dashboards.
  imports = [./holochain-services.nix];

  options.services.holochain-grafana = {
    enable = lib.mkEnableOption "Prometheus + Grafana observability for Holochain fleet";

    grafanaPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port Grafana listens on.";
    };

    prometheusPort = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port Prometheus listens on.";
    };

    scrapeTargets = lib.mkOption {
      type = lib.types.either (lib.types.listOf lib.types.str) (lib.types.attrsOf (lib.types.submodule {
        options = {
          address = lib.mkOption {
            type = lib.types.str;
            example = "edgenode-01:9100";
            description = "The node's node_exporter, as host:port.";
          };
          site = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "Sensorica lab";
            description = "Where the node is, shown beside its name. Left out of its series when null.";
          };
        };
      }));
      default = [];
      description = ''
        The node_exporter of every node Prometheus scrapes, and the name each
        node goes by on the dashboards. Prometheus attaches the name to every
        series from the target as the `node` label, so a node that is down is
        still shown by its name.

        As an attribute set, each key is the node's name, and the value gives
        its `address` (host:port) and, optionally, its `site`, which becomes a
        `site` label. As a list of host:port strings, each node is named after
        the host part of its address, except that a loopback address
        (127.0.0.1, localhost, ::1) takes this machine's
        `networking.hostName`. A list entry given by an IP address therefore
        goes by that address on every dashboard, and evaluation warns about
        it: give such a node a name with the attribute set form.

        No two targets may go by the same name: the dashboards aggregate by
        `node`, so two targets named alike would read as one machine. Two
        list entries on one host (two ports of a loopback, say) need the
        attribute set form.
      '';
      example = lib.literalExpression ''
        {
          lab-1 = { address = "edgenode-01:9100"; site = "Sensorica lab"; };
          lab-2 = { address = "edgenode-02:9100"; site = "Sensorica lab"; };
          homelab.address = "100.64.0.7:9100";
        }
      '';
    };

    states = {
      staleAfterSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 90;
        description = ''
          How old a conductor's readings may get before every DHT of it reads
          "No fresh readings" and its conductor state reads stale. The default
          covers the metrics timer's 30 s interval plus the 15 s scrape, with
          margin; raise it with `conductorMetrics.interval`.
        '';
      };

      silentAfterSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 600;
        description = ''
          How long a DHT that knows peers may go without gossiping with any of
          them before it reads "Lost contact".
        '';
      };

      inStepShare = lib.mkOption {
        type = lib.types.numbers.between 0 1;
        default = 0.95;
        description = ''
          The share of its best peer's data a connected DHT must hold, on
          average over `shareWindow`, to read "In step" rather than "Catching
          up". A healthy DHT rarely holds everything its best peer does, since
          new data is always on its way, so 1 would read a working network as
          behind for good; 0.95 is what the Sensorica Moss node's DHTs held on
          2026-09-27.
        '';
      };

      shareWindow = lib.mkOption {
        type = lib.types.strMatching "[0-9]+(ms|s|m|h|d|w|y)";
        default = "10m";
        description = ''
          The window, as a Prometheus duration, the held share is averaged
          over, so a DHT does not flap between "In step" and "Catching up" at
          every write.
        '';
      };

      historyWindow = lib.mkOption {
        type = lib.types.strMatching "[0-9]+(ms|s|m|h|d|w|y)";
        default = "24h";
        description = ''
          How far back, as a Prometheus duration, a DHT with no peer is
          remembered to have had one. Within it the DHT reads "Lost contact";
          a DHT that had nobody in all of it, on a DNA no other node of the
          fleet runs, reads "No one else yet", which is normal for a node that
          is alone.
        '';
      };
    };

    scrapeInterval = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      description = ''
        How often Prometheus scrapes its targets. Prometheus itself defaults to
        one minute, which for a lab fleet of a handful of nodes draws a
        fifteen-minute window as about fifteen points, and makes `rate()` over
        a short range flat or empty. The conductor metrics timer writes every
        30 s by default, so this is deliberately below it.
      '';
    };

    adminUser = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Grafana administrator account.";
    };

    adminPassword = lib.mkOption {
      type = lib.types.str;
      default = "workshop2026";
      description = ''
        Grafana administrator password. The default is the workshop's shared
        password, kept as a default so a fleet works out of the box on a lab
        network.

        It ends up world-readable in the Nix store, so it is a lab convenience
        and not a secret, and nixpkgs warns about it on every evaluation. On
        anything reachable from outside the lab use `adminPasswordFile`, which
        takes precedence over this option.
      '';
    };

    adminPasswordFile = lib.mkOption {
      # Not a store path: a path literal in a flake would copy the password
      # into the world-readable store, the one thing this option exists to avoid.
      type = lib.types.nullOr (lib.types.pathWith {
        inStore = false;
        absolute = true;
      });
      default = null;
      example = "/var/lib/secrets/grafana-admin-password";
      description = ''
        Path on the target machine to a file holding the Grafana administrator
        password. When set it takes precedence over `adminPassword`, and the
        password never enters the Nix store: systemd hands the file to Grafana
        as a credential (`LoadCredential`), and Grafana reads it through a
        `$__file{...}` reference.

        Because systemd reads it, the file can stay owned by root with mode
        0400, and it can be created before Grafana (or its user) exists.
        Create it on the node before the first deploy, for example:

        ```
        sudo install -d -m 0700 /var/lib/secrets
        sudo install -m 0400 /dev/null /var/lib/secrets/grafana-admin-password
        printf '%s' 'the-password' | sudo tee /var/lib/secrets/grafana-admin-password > /dev/null
        ```

        If the file is missing, grafana.service fails to start and its journal
        names the path.

        The path must survive a reboot, so `/run` is the wrong place for it
        unless a secrets manager repopulates it at boot.
      '';
    };

    secretKeyFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.pathWith {
        inStore = false;
        absolute = true;
      });
      default = null;
      example = "/var/lib/secrets/grafana-secret-key";
      description = ''
        Path on the target machine to a file holding Grafana's
        `security.secret_key`, the key it encrypts data source secrets with.
        Since NixOS 26.05 Grafana has no default key and refuses to evaluate
        without one.

        When null, the module generates a random key once, at first boot, in
        `''${services.grafana.dataDir}/secret_key` (mode 0400, owned by
        `grafana`) and keeps it across rebuilds, so the key never enters the
        Nix store. Set this only to share one key between machines or to
        restore one from a backup; like `adminPasswordFile`, it is handed over
        by systemd and can stay root-owned.
      '';
    };

    dashboards = lib.mkOption {
      type = lib.types.path;
      default = ./dashboards;
      defaultText = lib.literalExpression "./dashboards";
      description = ''
        Directory of Grafana dashboard JSON files to provision. Everything in
        it is loaded at startup and re-read every 30 seconds. The module ships
        four, each titled with the question it answers and all tagged
        `holochain`: `holochain-now` ("Is the Holochain network working?"),
        the room screen and Grafana's home page; `holochain-fleet` ("Which
        Holochain node needs attention?"), for whoever runs the fleet;
        `holochain-node` ("Is this node working, app by app?"), one machine;
        and `holochain-network` ("Is this app in step on every node?"), one
        app network across every machine. They read the recording rules of
        holochain-rules.nix, so they agree on every state.

        For a directory in the Nix store, the module sets Grafana's home page
        (`services.grafana.settings.dashboards.default_home_dashboard_path`,
        at default priority, so a definition of your own wins): its
        `holochain-now.json` when it has one, otherwise a copy of Grafana's
        own home page. The choice is made while building, so a directory
        inside a package is not built during evaluation.

        A directory in the Nix store (a path in your flake, or a directory
        inside a flake input or package such as `"''${inputs.x}/dashboards"`)
        has every dashboard's `units` textbox variable set from
        `overviewUnits` on its way in, every field override matched by name
        to `name` given the units' names as value mappings, and the
        `room_app`, `room_part` and `room_label` constants set from `room`
        when that is set. Every threshold step that names a `states` option
        in its `fromOption` key takes that option's value, and the sentences
        that quote a state's threshold quote the value given, so the colours
        and the words agree with the state the rules compute. A directory
        outside the store, or a
        store path written as a bare string that carries no Nix string
        context, is provisioned as it is.
      '';
    };

    overviewUnits = lib.mkOption {
      # A list is what this option took before units had names; each of its
      # entries becomes a unit without one.
      type =
        lib.types.coercedTo (lib.types.listOf lib.types.str) (units: lib.genAttrs units (_: null))
        (lib.types.attrsOf (lib.types.nullOr lib.types.str));
      default = {};
      example = lib.literalExpression ''
        {
          "caddy.service" = "Web server";
          "restic-backups-.*" = "Backups";
        }
      '';
      description = ''
        systemd units to watch on every node on top of the ones each node
        lists itself, each with the name a person reads for it. The keys are
        units, the values their names; a unit whose name is null, or an entry
        of a plain list of units, is shown by its unit name.

        Every node lists its own services in
        `services.holochain-services.units`, filled from the modules enabled
        on it (the conductor, the HTTP gateway, the local bootstrap and relay,
        the Wind Tunnel runner, Prometheus, Grafana, and the services beside
        them), and publishes that list through node_exporter. This option is
        for what a node does not list: a machine that does not run these
        modules, or a unit of your own on every machine. Its default is empty,
        so what is watched follows each node's configuration.

        Each key is a regular expression Prometheus matches against the whole
        unit name, suffix included, so `restic-backups-.*` works, and its name
        is given to every unit it matches. A unit is watched on each node that
        runs it, and a node that does not run it has no row for it, so one set
        serves a fleet whose machines run different things. A unit a node
        lists itself keeps the name the node gives it.

        The watched units reach the recording rules (`holochain:service_watched`
        and `holochain:service_state`), which the node page's "Is each
        service on this machine running?", the fleet page's "Which services
        are not running?" and the room screen's machine tiles read. For a dashboard of your own, the
        keys are also joined with `|` into the default of any `units` textbox
        variable, and every field override matched by name to `name` (the
        unit label of `node_systemd_unit_state`) gets one regex value mapping
        per named unit.

        The `holochain:node_problem` rule, which the problem lists read, gives
        every failed unit on the node a sentence of its own whether it is
        watched or not, except device, scope and slice units, which the
        node_exporter flags these modules set leave out, naming it by its
        watched name or, when it has none, by its unit name.
      '';
    };

    room = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          app = lib.mkOption {
            type = lib.types.str;
            example = "requests-and-offers";
            description = "The installed_app_id of an app this module's fleet installs from Nix.";
          };
          part = lib.mkOption {
            type = lib.types.str;
            example = "requests_and_offers";
            description = "The role of the app whose writes the room follows.";
          };
          label = lib.mkOption {
            type = lib.types.str;
            example = "Requests & Offers";
            description = "The name the room screen gives that app.";
          };
        };
      });
      default = null;
      description = ''
        The one app part a room screen follows writes in. Rendered into the
        constant variables `room_app`, `room_part` and `room_label` of every
        provisioned dashboard that declares them; when null, those variables
        keep the defaults their dashboard gives them.

        An app installed by hand in Moss is not a good choice: its id changes
        with every installation and holds `$`, which Grafana reads as a
        variable.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall ports for Grafana, Prometheus, and node_exporter.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_port = cfg.grafanaPort;
          http_addr = "0.0.0.0";
          domain = "localhost";
          root_url = "http://localhost:${toString cfg.grafanaPort}/";
        };
        security = {
          admin_user = cfg.adminUser;

          # `$__file{...}` is Grafana's file provider: the value is read from
          # the path by the running service, so nothing but the path reaches
          # the Nix store. nixpkgs recognises this form and drops its
          # plaintext-password warning.
          admin_password =
            if cfg.adminPasswordFile != null
            then credential "admin_password"
            else cfg.adminPassword;

          # Same file provider: only the path reaches the store.
          secret_key = secretKeyPath;
        };
        analytics.reporting_enabled = false;
        dashboards.default_home_dashboard_path = lib.mkIf dashboardsInStore (lib.mkDefault "${homeDashboard}");
      };

      provision = {
        enable = true;

        # Provisioned by uid, not by name: a dashboard that names its data
        # source by title breaks the moment someone renames it.
        datasources.settings = {
          apiVersion = 1;
          datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              uid = datasourceUid;
              access = "proxy";
              url = "http://127.0.0.1:${toString cfg.prometheusPort}";
              isDefault = true;
            }
          ];
        };

        dashboards.settings = {
          apiVersion = 1;
          providers = [
            {
              name = "holochain";
              type = "file";
              updateIntervalSeconds = 30;
              # The files come from the Nix store, so letting the UI write back
              # would produce edits that the next rebuild silently discards.
              allowUiUpdates = false;
              disableDeletion = true;
              options = {
                path = provisionedDashboards;
                foldersFromFilesStructure = false;
              };
            }
          ];
        };
      };
    };

    systemd.services.grafana.serviceConfig.LoadCredential =
      lib.optional (cfg.adminPasswordFile != null) "admin_password:${toString cfg.adminPasswordFile}"
      ++ lib.optional (cfg.secretKeyFile != null) "secret_key:${toString cfg.secretKeyFile}";

    # Generates the key once and never rotates it: Grafana cannot decrypt what
    # it stored under an older key, and nixpkgs offers no rotation path.
    systemd.services.grafana-secret-key = lib.mkIf (cfg.secretKeyFile == null) {
      description = "Generate Grafana's secret key on first boot";
      wantedBy = ["grafana.service"];
      before = ["grafana.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        dir=${lib.escapeShellArg config.services.grafana.dataDir}
        key=${lib.escapeShellArg generatedSecretKey}
        install -d -m 0700 -o grafana -g grafana "$dir"
        if [ ! -s "$key" ]; then
          umask 0377
          head -c 32 /dev/urandom | base64 > "$key.tmp"
          chown grafana:grafana "$key.tmp"
          mv "$key.tmp" "$key"
        fi
      '';
    };

    services.prometheus = {
      enable = true;
      port = cfg.prometheusPort;

      globalConfig.scrape_interval = cfg.scrapeInterval;

      # One static config per target, so each carries its own node's name.
      # Exporters never write a `node` label of their own: with honor_labels
      # off, Prometheus would keep the target's and rename theirs.
      scrapeConfigs = [
        {
          job_name = "holochain-nodes";
          static_configs =
            map (target: {
              targets = [target.address];
              labels =
                {inherit (target) node;}
                // lib.optionalAttrs (target.site != null) {inherit (target) site;};
            })
            targets;
        }
      ];

      ruleFiles = [rulesFile];
    };

    warnings =
      map (target: ''
        services.holochain-grafana.scrapeTargets: the node at ${target.address} goes by the address "${target.node}" on the dashboards, since a list names each node after its host. Give it a name with the attribute set form: scrapeTargets = { <name> = { address = "${target.address}"; }; }.
      '')
      addressNamed;

    assertions = [
      {
        assertion = sharedNodeNames == [];
        message = ''
          services.holochain-grafana.scrapeTargets: more than one target goes by the node name ${lib.concatMapStringsSep ", " (name: "\"${name}\"") sharedNodeNames}. The dashboards aggregate by node, so they would read as one machine. Name each target with the attribute set form: scrapeTargets = { <name> = { address = "host:port"; }; }.
        '';
      }
    ];

    # Monitor node also exports its own system metrics. `mkDefault` throughout,
    # because a monitor node that is also an edgenode has these set by
    # holochain-edgenode's metricsExporter, which knows about the textfile
    # collector this module has no business configuring.
    services.prometheus.exporters.node = {
      enable = lib.mkDefault true;
      port = lib.mkDefault 9100;
      # The textfile collector publishes this machine's list of services.
      enabledCollectors = lib.mkDefault ["systemd" "textfile"];
      # Counts failed mount units too, which node_exporter leaves out by
      # default. The same flags as holochain-edgenode's, and at mkDefault so
      # that module's list replaces this one: node_exporter refuses to start
      # when a flag is given twice.
      extraFlags = lib.mkDefault [
        "--collector.systemd.unit-exclude=.+[.](device|scope|slice)"
        "--collector.textfile.directory=${defaultTextfileDirectory}"
        # Restart counts, so a service that keeps failing and restarting
        # reads Failed rather than Starting.
        "--collector.systemd.enable-restarts-metrics"
      ];
    };

    # This machine's own services, by name. Its textfile directory is the one
    # the node_exporter defaults above read; an edgenode's replaces it, with
    # the flags.
    services.holochain-services = {
      units = {
        "prometheus.service" = "Metrics database";
        "grafana.service" = "Dashboards";
      };
      textfileDirectory = lib.mkDefault defaultTextfileDirectory;
    };
    # An edgenode creates the directory itself, owned by its user.
    systemd.tmpfiles.rules = lib.mkIf (!edgenodeExports) ["d ${defaultTextfileDirectory} 0755 root root - -"];

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.grafanaPort cfg.prometheusPort 9100];
    };
  };
}
