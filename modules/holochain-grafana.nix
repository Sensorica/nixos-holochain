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
  ...
}: let
  cfg = config.services.holochain-grafana;

  # The dashboard JSON refers to its data source by this uid rather than by
  # name, so the file stays valid whatever the datasource is called.
  datasourceUid = "holochain-prometheus";

  generatedSecretKey = "${config.services.grafana.dataDir}/secret_key";
  secretKeyPath =
    if cfg.secretKeyFile != null
    then toString cfg.secretKeyFile
    else generatedSecretKey;
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
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/var/lib/secrets/grafana-admin-password";
      description = ''
        Path on the target machine to a file holding the Grafana administrator
        password. When set it takes precedence over `adminPassword`, and the
        password never enters the Nix store: the path is handed to Grafana as a
        `$__file{...}` reference and read by the running service.

        The file is read by the `grafana` user, so it has to be readable by it.
        Create it on the node before the first `colmena apply`, for example:

        ```
        sudo install -d -m 0755 /var/lib/secrets
        sudo install -o grafana -g grafana -m 0400 /dev/null /var/lib/secrets/grafana-admin-password
        printf '%s' 'the-password' | sudo tee /var/lib/secrets/grafana-admin-password > /dev/null
        ```

        The path must survive a reboot, so `/run` is the wrong place for it
        unless a secrets manager repopulates it at boot.
      '';
    };

    secretKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
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
        restore one from a backup.
      '';
    };

    dashboards = lib.mkOption {
      type = lib.types.path;
      default = ./dashboards;
      defaultText = lib.literalExpression "./dashboards";
      description = ''
        Directory of Grafana dashboard JSON files to provision. Everything in
        it is loaded at startup and re-read every 30 seconds. The module ships
        `holochain-fleet.json` (uid `holochain-fleet`), which draws CPU, memory
        and host network from node_exporter and the conductor's own
        `holochain_*` series from the edgenode module's metrics timer.
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
            then "$__file{${toString cfg.adminPasswordFile}}"
            else cfg.adminPassword;

          # Same file provider: only the path reaches the store.
          secret_key = "$__file{${secretKeyPath}}";
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
                path = cfg.dashboards;
                foldersFromFilesStructure = false;
              };
            }
          ];
        };
      };
    };

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
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.grafanaPort cfg.prometheusPort 9100];
    };
  };
}
