# modules/holochain-services.nix
#
# The services a node runs, as the dashboards show them: every nixos-holochain
# module imports this file and names the units it creates when it is enabled,
# so the list follows the configuration instead of being kept by hand. The
# node publishes it through node_exporter's textfile collector, one
# `holochain_service_info` line per unit, and Prometheus attaches the node's
# name to it like to any other series; the recording rules join it to
# `node_systemd_unit_state` to read each service's state. Each node publishes
# its own list, so a monitor learns what a Holoport runs from the Holoport,
# not from its own configuration.
#
# A service that can be up and still not answer (the bootstrap server) also
# declares a health check here. One timer runs them all and writes
# `holochain_service_healthy` and the time it last looked, so "running but not
# answering" and "nobody has looked lately" are both visible.
#
# Nothing here is written unless `textfileDirectory` names the directory
# node_exporter reads. The edgenode module sets it when it runs the exporter,
# and the grafana module on a monitor; any other machine that runs
# node_exporter with a textfile collector sets it by hand.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.holochain-services;

  # The modules whose units are listed. `or false`, because a machine may
  # import this file through one module without having the others.
  holochainModules = ["holochain-edgenode" "holochain-grafana" "holochain-http-gateway" "holochain-windtunnel" "holochain-bootstrap"];
  anyEnabled = lib.any (name: config.services.${name}.enable or false) holochainModules;

  # A Prometheus label value: backslash, double quote and newline escaped.
  labelValue = value: builtins.replaceStrings ["\\" "\"" "\n"] ["\\\\" "\\\"" "\\n"] value;

  infoFile = pkgs.writeText "holochain-services.prom" (''
      # HELP holochain_service_info A service this node runs that the Holochain dashboards watch, by the name a person reads for it (service) and, for a conductor, the conductor label its readings carry. Always 1.
      # TYPE holochain_service_info gauge
    ''
    + lib.concatStrings (lib.mapAttrsToList (unit: service: ''
        holochain_service_info{${lib.optionalString (service.conductor != null) ''conductor="${labelValue service.conductor}",''}name="${labelValue unit}",service="${labelValue service.name}"} 1
      '')
      cfg.units));

  # Every check runs before anything is written, so the file is written in
  # one piece, each family's lines together, as node_exporter requires.
  healthScript = pkgs.writeShellScript "holochain-service-health" ''
    set -u
    dir=${lib.escapeShellArg cfg.textfileDirectory}
    now=$(${pkgs.coreutils}/bin/date +%s)
    ${lib.concatStrings (lib.imap0 (i: unit: let
      check = cfg.healthChecks.${unit};
    in ''
      if ${pkgs.curl}/bin/curl -sf -o /dev/null --max-time ${toString check.timeoutSeconds} ${lib.optionalString check.insecure "-k "}${lib.escapeShellArg check.url}; then
        healthy_${toString i}=1
      else
        healthy_${toString i}=0
      fi
    '') (lib.attrNames cfg.healthChecks))}
    {
      echo '# HELP holochain_service_healthy 1 when the service answered its health check, 0 when it did not.'
      echo '# TYPE holochain_service_healthy gauge'
      ${lib.concatStrings (lib.imap0 (i: unit: ''
      echo ${lib.escapeShellArg ''holochain_service_healthy{name="${labelValue unit}"}''} "$healthy_${toString i}"
    '') (lib.attrNames cfg.healthChecks))}
      echo '# HELP holochain_service_health_timestamp_seconds When the service health checks last ran, as a Unix time.'
      echo '# TYPE holochain_service_health_timestamp_seconds gauge'
      ${lib.concatStrings (map (unit: ''
      echo ${lib.escapeShellArg ''holochain_service_health_timestamp_seconds{name="${labelValue unit}"}''} "$now"
    '') (lib.attrNames cfg.healthChecks))}
    } > "$dir/.holochain-service-health.prom.tmp"
    mv "$dir/.holochain-service-health.prom.tmp" "$dir/holochain-service-health.prom"
  '';
in {
  options.services.holochain-services = {
    units = lib.mkOption {
      type = lib.types.attrsOf (lib.types.coercedTo lib.types.str (name: {inherit name;}) (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            example = "Local bootstrap and relay";
            description = "The name a person reads for the unit on the dashboards.";
          };
          conductor = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "Workshop";
            description = ''
              For a unit that runs a Holochain conductor, the `conductor` label
              its readings carry (`services.holochain-edgenode.conductorMetrics.name`
              for an edgenode). The service then reads Not answering when the
              conductor does not answer its admin interface, and No fresh
              readings when its readings are old, although systemd says the
              unit is active. A conductor that no listed unit claims is shown
              as a service of its own, "Holochain conductor (<conductor>)", as
              the edgenode names the unit that runs a conductor under a name
              other than the default: a Moss node whose readings carry
              `conductor="Moss"` reads "Holochain conductor (Moss)".
            '';
          };
        };
      }));
      default = {};
      example = lib.literalExpression ''
        {
          "caddy.service" = "Web server";
          "moss-node-metrics.timer" = "Moss readings (timer)";
        }
      '';
      description = ''
        The systemd units this node runs that the Holochain dashboards watch,
        each with the name a person reads for it; a value is that name, or
        `{ name; conductor; }` for a unit that runs a conductor.

        Filled from the configuration: every nixos-holochain module that is
        enabled adds the units it creates (the conductor, the app installer
        when there are apps, the conductor readings timer when
        `conductorMetrics` is on, the HTTP gateway, the local bootstrap and
        relay, the Wind Tunnel runner, and on a monitor Prometheus and
        Grafana), and, on a machine where any of them is enabled, the
        services beside them that are enabled here: node_exporter, sshd,
        Tailscale and the Nix daemon's socket. Add a unit of your own the way
        any attribute set option merges; override a name with `lib.mkForce`
        on that one attribute.

        Published as `holochain_service_info` through node_exporter's textfile
        collector when `textfileDirectory` is set. The node page's "Is each
        service on this machine running?" lists each of them with its state,
        the fleet page lists the ones that are not running, and the room
        screen's machine tile reads "A service is down" while one has failed,
        keeps failing and restarting, has stopped or does not answer. A unit
        systemd does not run has no row; evaluation warns about a listed unit
        this configuration does not define.
        `services.holochain-grafana.overviewUnits`, on the monitor, adds units
        to watch on every node on top of these.
      '';
    };

    healthChecks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          url = lib.mkOption {
            type = lib.types.str;
            example = "http://127.0.0.1:443/health";
            description = "A URL that answers with a success status while the service works.";
          };
          insecure = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Accept any TLS certificate. For a check that reaches a service by
              its loopback address while its certificate names the host.
            '';
          };
          timeoutSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 5;
            description = "How long the check waits for an answer before it reads the service as not answering.";
          };
        };
      });
      default = {};
      description = ''
        Health checks, keyed by the unit they check, which should also be in
        `units`. A timer runs every one every 30 seconds and writes
        `holochain_service_healthy` (1 or 0) and
        `holochain_service_health_timestamp_seconds` to
        `holochain-service-health.prom` in `textfileDirectory`. A service
        whose unit is active reads Not answering on the dashboards when its
        check fails, and No fresh readings when the last check is older than
        `services.holochain-grafana.states.staleAfterSeconds`. The bootstrap
        module adds its `/health` here.
      '';
    };

    textfileDirectory = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/lib/prometheus-node-exporter-text-files";
      description = ''
        The directory node_exporter's textfile collector reads on this
        machine, where the list of services and the health readings are
        written. Set by `services.holochain-edgenode` when its
        `metricsExporter` is on, and by `services.holochain-grafana` on a
        monitor; on another machine that runs node_exporter with a textfile
        collector of its own (a machine that only runs the bootstrap server,
        say), set it to that collector's directory. Null writes nothing, and
        that machine's services are then missing from the dashboards.
      '';
    };
  };

  config = lib.mkMerge [
    {
      services.holochain-services.units = lib.mkIf anyEnabled (lib.mkMerge [
        (lib.mkIf config.services.prometheus.exporters.node.enable {"prometheus-node-exporter.service" = "Machine readings";})
        # With startWhenNeeded, NixOS runs sshd from a socket and defines no
        # sshd.service, only sshd.socket and one sshd@ instance per login.
        (lib.mkIf config.services.openssh.enable (
          if config.services.openssh.startWhenNeeded
          then {"sshd.socket" = "Remote login";}
          else {"sshd.service" = "Remote login";}
        ))
        (lib.mkIf config.services.tailscale.enable {"tailscaled.service" = "Private network (Tailscale)";})
        # NixOS starts nix-daemon.service on demand, so the service is inactive
        # on an idle node that is perfectly healthy; its socket is not.
        (lib.mkIf config.nix.enable {"nix-daemon.socket" = "Nix";})
      ]);

      # A listed unit systemd does not run has no node_systemd_unit_state
      # series, so it has no row at all on the pages, rather than a row that
      # says something is wrong. Only units this configuration declares as
      # services, sockets or timers are checked; one that a package ships and
      # the configuration never mentions may be warned about wrongly.
      warnings = let
        tables = {
          service = "services";
          socket = "sockets";
          timer = "timers";
        };
        declared = unit: let
          parts = builtins.match "(.+)[.](service|socket|timer)" unit;
        in
          parts == null || config.systemd.${tables.${builtins.elemAt parts 1}} ? ${builtins.head parts};
        missing = builtins.filter (unit: !declared unit) (builtins.attrNames cfg.units);
      in
        lib.optional (anyEnabled && missing != []) ''
          services.holochain-services.units lists ${lib.concatMapStringsSep ", " (unit: "\"${unit}\"") missing}, which this configuration does not define as a systemd unit. A unit systemd does not run has no row on the Holochain dashboards, so it would be missing without a word. Remove it, or list the unit that actually runs.
        '';
    }

    (lib.mkIf (anyEnabled && cfg.textfileDirectory != null) {
      # A link into the store, replaced on every activation, so the list is
      # always the running configuration's.
      systemd.tmpfiles.rules = lib.optional (cfg.units != {}) "L+ ${cfg.textfileDirectory}/holochain-services.prom - - - - ${infoFile}";

      systemd.services.holochain-service-health = lib.mkIf (cfg.healthChecks != {}) {
        description = "Check the Holochain services that answer health checks, for node_exporter";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${healthScript}";
          TimeoutStartSec = "60s";
          # Root, to write into a textfile directory another user may own,
          # with no other privilege.
          CapabilityBoundingSet = ["CAP_DAC_OVERRIDE"];
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ReadWritePaths = [cfg.textfileDirectory];
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
          RestrictNamespaces = true;
          LockPersonality = true;
          SystemCallArchitectures = "native";
        };
      };

      systemd.timers.holochain-service-health = lib.mkIf (cfg.healthChecks != {}) {
        description = "Periodic health checks of the Holochain services";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitActiveSec = "30s";
          AccuracySec = "1s";
          Unit = "holochain-service-health.service";
        };
      };
    })
  ];
}
