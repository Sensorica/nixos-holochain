# modules/holochain-grafana.nix
#
# Prometheus + Grafana observability module for a Holochain fleet.
# Enable on the designated monitor node; all peer nodes should set
#   services.holochain-edgenode.metricsExporter.enable = true;
#   services.holochain-edgenode.conductorMetrics.enable = true;
# the first gives the host series, the second the holochain_* series the
# provisioned dashboard is built around.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.holochain-grafana;

  # A dashboard's variable defaults live in its JSON, and the JSON reaches
  # Grafana read-only, so the only way a module option can set one is by
  # rewriting the file on its way into the store. Every provisioned dashboard
  # with a textbox variable named `units` gets overviewUnits as its default;
  # everything else in the directory is copied unchanged. A directory outside
  # the store is read by Grafana at runtime and cannot be rewritten here, so it
  # is passed through as it is.
  #
  # "In the store" means a path literal, or a string that points into the
  # store and carries the context that makes it a build input, such as
  # "''${inputs.x}/dashboards". lib.isStorePath alone would miss the second:
  # it is true only for a top-level store path, not for a directory inside one.
  unitsRegex = lib.concatStringsSep "|" cfg.overviewUnits;
  dashboardsPath = toString cfg.dashboards;
  dashboardsInStore =
    builtins.isPath cfg.dashboards
    || (lib.hasPrefix "${builtins.storeDir}/" dashboardsPath && builtins.hasContext dashboardsPath);
  provisionedDashboards =
    if dashboardsInStore
    then
      pkgs.runCommand "holochain-grafana-dashboards" {
        nativeBuildInputs = [pkgs.jq];
        inherit unitsRegex;
      } ''
        cp -rL --no-preserve=mode ${cfg.dashboards} $out
        find $out -type f -name '*.json' | while IFS= read -r f; do
          jq --arg units "$unitsRegex" '
            def isUnits: .name == "units" and .type == "textbox";
            if type == "object" and ((.templating.list // []) | any(isUnits))
            then .templating.list |= map(
              if isUnits
              then .query = $units
                | .current = {text: $units, value: $units}
                | .options = [{selected: true, text: $units, value: $units}]
              else .
              end)
            else .
            end
          ' "$f" > "$f.tmp"
          mv "$f.tmp" "$f"
        done
      ''
    else cfg.dashboards;

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
in {
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
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Prometheus node_exporter targets across the fleet (host:port).";
      example = lib.literalExpression ''
        [ "edgenode-01:9100" "edgenode-02:9100" "edgenode-03:9100"
          "edgenode-04:9100" "edgenode-05:9100" ]
      '';
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
        `holochain-fleet.json` (uid `holochain-fleet`): an Overview row saying
        per node whether the node, its conductor and its services are up, a
        Holochain row drawn from the edgenode module's metrics timer, and a
        Host health row drawn from node_exporter.

        A directory in the Nix store (a path in your flake, or a directory
        inside a flake input or package such as `"''${inputs.x}/dashboards"`)
        has every dashboard's `units` textbox variable set from
        `overviewUnits` on its way in. A directory outside the store, or a
        store path written as a bare string that carries no Nix string
        context, is provisioned as it is.
      '';
    };

    overviewUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "holochain-conductor.service"
        "holochain-happ-installer.service"
        "holochain-conductor-metrics.timer"
        "holochain-http-gateway.service"
        "(podman|docker)-wind-tunnel-runner.service"
        "prometheus.service"
        "prometheus-node-exporter.service"
        "grafana.service"
        "sshd.service"
        "tailscaled.service"
        "nix-daemon.socket"
      ];
      example = lib.literalExpression ''
        [ "holochain-conductor.service" "holochain-happ-installer.service"
          "sshd.service" "caddy.service" "restic-backups-.*" ]
      '';
      description = ''
        systemd units the dashboard's Services panel shows for every node,
        read from node_exporter's systemd collector (`node_systemd_unit_state`).
        The default covers the long-running units the nixos-holochain modules
        create, plus the services a fleet node usually runs beside them. Two
        one-shot helpers are left out: `holochain-conductor-metrics.service`
        sits idle between runs, so its timer is listed instead, and
        `grafana-secret-key.service` runs once at boot; if either fails, the
        Fleet status panel counts it. The Nix daemon is listed by its socket:
        NixOS starts `nix-daemon.service` on demand, so the service is
        inactive on an idle node that is perfectly healthy.

        The panel has one row per node and one column per unit that some
        selected node has. A unit one node runs and another does not shows as
        absent on the second node's row; a unit no selected node runs has no
        column at all, so one list serves a whole fleet whose machines run
        different things.

        Each entry is a regular expression Prometheus matches against the
        whole unit name, suffix included, so `restic-backups-.*` works. The
        entries are joined with `|` into the default of the dashboard's
        `units` variable; a viewer can type another regex in the browser,
        which lives in that page's URL and is never saved to the dashboard.

        Setting this option replaces the default list. To add a unit and keep
        the defaults, define it with `lib.mkOptionDefault`, which merges with
        the default instead of overriding it:
        `overviewUnits = lib.mkOptionDefault [ "caddy.service" ];`.

        This list only picks what the Services panel draws. The Fleet status
        panel counts every failed unit on the node whatever is listed here,
        except device, scope and slice units, which the node_exporter flags
        these modules set leave out.
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

      scrapeConfigs = [
        {
          job_name = "holochain-nodes";
          static_configs = [{targets = cfg.scrapeTargets;}];
        }
      ];
    };

    # Monitor node also exports its own system metrics. `mkDefault` throughout,
    # because a monitor node that is also an edgenode has these set by
    # holochain-edgenode's metricsExporter, which knows about the textfile
    # collector this module has no business configuring.
    services.prometheus.exporters.node = {
      enable = lib.mkDefault true;
      port = lib.mkDefault 9100;
      enabledCollectors = lib.mkDefault ["systemd"];
      # Counts failed mount units too, which node_exporter leaves out by
      # default. The same flag as holochain-edgenode's, and at mkDefault so
      # that module's list replaces this one: node_exporter refuses to start
      # when the flag is given twice.
      extraFlags = lib.mkDefault ["--collector.systemd.unit-exclude=.+[.](device|scope|slice)"];
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.grafanaPort cfg.prometheusPort 9100];
    };
  };
}
