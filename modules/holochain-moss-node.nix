# A Moss always-online node as a NixOS service: wdocker's daemon, the headless
# part of Moss, hosting one Moss group and the tools its stewards tagged for
# always-online nodes, plus its readings on the dashboards.
#
# The daemon reads the conductor password on stdin and needs no terminal
# (`wdaemon NAME`, the same entry point `vmTestWdocker` starts), so systemd
# runs it under its own user with the password passed as a credential from a
# root-only file. It creates the conductor on its first start. Joining the
# group is the one step that still needs a person: `wdocker join-group`
# prompts at a terminal for the password, a profile name and a description,
# and the invite link carries the group's network seed, which must never reach
# a file. `moss-node join "INVITE_LINK"` runs it as the service's user and
# restarts the daemon, which pings Moss only for the groups present when it
# starts (docs/moss-node.md).
#
# The readings are nixos-holochain's own conductor exporter under the conductor
# name "Moss", beside the edgenode's (one program, one set of HELP texts, which
# node_exporter needs when two files share its textfile directory, #47). wdocker
# picks a random admin port and allowed origin at every start and writes both
# into its conductor config, so the exporter asks a small script for them on
# every run. Ported from athanor's mossNodeMetrics (athanor 539e648).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.holochain-moss-node;
  edge = config.services.holochain-edgenode;
  stateDir = "/var/lib/moss-node";
  wdockerData = "${stateDir}/.local/share/wdocker";
  out = "${toString edge.metricsExporter.textfileDirectory}/moss-node.prom";
  metricsState = "/var/lib/moss-node-metrics";

  exporter = pkgs.callPackage ../packages/holochain-conductor-exporter.nix {
    hc = edge.hcPackage;
  };

  # wdocker as the service's user, with the service's HOME, so its commands
  # find the conductor the daemon runs.
  asNode = pkgs.writeShellScript "moss-node-as-user" ''
    exec ${pkgs.util-linux}/bin/runuser -u moss-node -- env HOME=${stateDir} ${cfg.package}/bin/wdocker "$@"
  '';

  helper = pkgs.writeShellScriptBin "moss-node" ''
    set -eu
    name=${lib.escapeShellArg cfg.name}
    usage() {
      cat <<'EOF'
    Usage: moss-node COMMAND

      join "INVITE_LINK"  join the Moss group (asks for the conductor password,
                          a profile name and a description), then restart the
                          node so Moss sees it online. Keep the link out of
                          shell history: start the line with a space.
      status              the daemon's state, its groups and its apps
      logs                follow the daemon's journal
      restart             restart the daemon
      wdocker ARGS...     any wdocker command, as the node's user

    Run as root (sudo moss-node ...).
    EOF
    }
    [ "$(id -u)" -eq 0 ] || { echo "moss-node: run as root (sudo moss-node ...)" >&2; exit 1; }
    cmd=''${1:-}
    [ $# -gt 0 ] && shift
    case $cmd in
      join)
        [ $# -eq 1 ] || { usage >&2; exit 2; }
        ${asNode} join-group "$name" "$1"
        echo "Restarting the node so Moss sees it online in the new group..."
        systemctl restart moss-node.service
        ;;
      status)
        systemctl --no-pager status moss-node.service | head -5 || true
        ${asNode} list
        ${asNode} list-groups "$name"
        ${asNode} list-apps "$name"
        ;;
      logs) exec journalctl -f -u moss-node.service ;;
      restart) exec systemctl restart moss-node.service ;;
      wdocker) exec ${asNode} "$@" ;;
      -h|--help|help|"") usage ;;
      *) usage >&2; exit 2 ;;
    esac
  '';

  # Port first, origin second, on one line, as the exporter's --admin expects.
  # Nothing when the conductor config is not there, which the exporter reads as
  # a conductor that is down.
  adminEndpoint = pkgs.writeShellScript "moss-admin-endpoint" ''
    PATH=${lib.makeBinPath [pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gnused]}
    cfgfile=$(find ${wdockerData} -path '*/conductors/${cfg.name}/conductor/conductor-config.yaml' 2>/dev/null | head -1)
    [ -n "$cfgfile" ] || exit 0
    port=$(grep -A3 admin_interfaces "$cfgfile" | grep -oE 'port: [0-9]+' | grep -oE '[0-9]+' | head -1)
    origin=$(grep -A6 admin_interfaces "$cfgfile" | grep -oE 'allowed_origins: .*' | sed -E 's/allowed_origins: //; s/["'"'"']//g')
    echo "$port $origin"
  '';

  # The names the exporter reads (see dht-metrics.jq): each named tool, the
  # part names of each tool kind, and the named tools as expected, so a tool
  # the conductor stops listing reads "Not running" instead of vanishing.
  staticNames = pkgs.writeText "moss-names.json" (builtins.toJSON {
    apps = lib.mapAttrs (_: name: {inherit name;}) cfg.appletNames;
    kinds = cfg.partNames;
    expected = lib.attrNames cfg.appletNames;
  });

  dashboards = pkgs.runCommand "holochain-moss-dashboards" {nativeBuildInputs = [pkgs.jq];} ''
    mkdir -p $out
    jq --arg title ${lib.escapeShellArg cfg.dashboard.title} '.title = $title' \
      ${./dashboards-moss/sensorica-moss-node.json} > $out/sensorica-moss-node.json
  '';
in {
  options.services.holochain-moss-node = {
    enable = lib.mkEnableOption "a Moss always-online node (wdocker's daemon) as a systemd service, with its readings";

    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        wdocker, with the Holochain binary it runs. The flake's
        `nixosModules.holochain-moss-node` sets it to its `wdocker-0_15`
        (Moss 0.15.8, Holochain 0.6.1).
      '';
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = "moss-node";
      example = "sensorica";
      description = "The wdocker conductor's name, a local label.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.str;
      example = "/var/lib/secrets/moss-node-password";
      description = ''
        A root-only file holding the conductor password, with no trailing
        newline. Only the path reaches the Nix store; systemd passes the file
        to the daemon as a credential and the daemon reads it on stdin. The
        same password is asked for once by `moss-node join`.
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "Moss group";
      example = "Sensorica";
      description = ''
        What the dashboards call the Moss group itself (every `group#` app on
        the conductor). The name is given from the exporter's second run on:
        its previous file says which group apps there are.
      '';
    };

    appletNames = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = {"applet#uhc$e$k..." = "General chat";};
      description = ''
        What the dashboards call each Moss tool, keyed by its installed_app_id
        (`applet#...`, as `moss-node status` prints it). A tool left out reads
        by its kind and a number (Vines 1, Vines 2). A tool named here is also
        expected: when the conductor does not list it, it reads "Not running".
      '';
    };

    partNames = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = {
        # dnas/ of lightningrodlabs/moss: the group DNA holds members' profiles
        # and the tools the group added, the foyer is the group's own chat,
        # and the assets DNA holds the relations between assets.
        Group = {
          group = "Members and tools";
          foyer = "Foyer";
          assets = "Asset links";
        };
        # lightningrodlabs/vines dna/workdir/happ.yaml: rVines bundles
        # threads.dna, rFiles files.dna.
        Vines = {
          rVines = "Messages";
          rFiles = "Files";
        };
      };
      description = ''
        What the dashboards call each part (DNA role) of each kind of Moss app,
        keyed by kind: "Group" for the group itself, else the tool's bundle name
        without Moss's leading "h". A role left out reads as its id with a
        one-letter prefix dropped.
      '';
    };

    dashboard = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.services.grafana.enable;
        defaultText = lib.literalExpression "config.services.grafana.enable";
        description = ''
          Provision the Moss node page in this machine's Grafana. It lists every
          Moss node the monitor's Prometheus scrapes, so the monitor node
          enables it even when it runs no Moss node itself.
        '';
      };
      title = lib.mkOption {
        type = lib.types.str;
        default = "Is the Moss group always online?";
        example = "Sensorica group on the Holoports";
        description = "The page's title.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = edge.enable && edge.metricsExporter.enable;
          message = "services.holochain-moss-node needs services.holochain-edgenode with its metricsExporter: the Moss readings go through the same exporter and textfile directory.";
        }
      ];

      users.users.moss-node = {
        isSystemUser = true;
        group = "moss-node";
        home = stateDir;
      };
      users.groups.moss-node = {};

      systemd.services.moss-node = {
        description = "Moss always-online node (wdocker daemon, conductor ${cfg.name})";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];
        environment.HOME = stateDir;
        serviceConfig = {
          User = "moss-node";
          Group = "moss-node";
          StateDirectory = "moss-node";
          StateDirectoryMode = "0700";
          WorkingDirectory = stateDir;
          LoadCredential = "password:${cfg.passwordFile}";
          ExecStart = "${pkgs.runtimeShell} -c 'exec ${cfg.package}/bin/wdaemon ${lib.escapeShellArg cfg.name} < \"$CREDENTIALS_DIRECTORY/password\"'";
          Restart = "on-failure";
          RestartSec = "30s";
          # The conductor alone takes about 900 MB; the daemon checks the
          # group's tools every five minutes.
          TimeoutStopSec = "60s";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
        };
      };

      environment.systemPackages = [helper];

      systemd.services.moss-node-metrics = {
        description = "Export the Moss node's conductor and per-DHT metrics for node_exporter";
        path = [pkgs.jq];
        serviceConfig = {
          Type = "oneshot";
          PrivateTmp = true;
          StateDirectory = "moss-node-metrics";
        };
        script = ''
          set -u
          # The group apps and every app's kind, from a textfile the exporter
          # wrote: a group gets its name, and a tool the conductor stops
          # listing keeps its kind. A missing or unreadable file costs only that.
          names() {
            if ! jq -n --slurpfile static ${staticNames} --rawfile seen "$1" \
                 --arg group ${lib.escapeShellArg cfg.group} -f ${./moss-node-names.jq} > /tmp/names.json; then
              cp ${staticNames} /tmp/names.json
            fi
          }
          export_to() {
            ${lib.getExe exporter} \
              --conductor Moss \
              --admin ${adminEndpoint} \
              --names /tmp/names.json \
              --out "$1" \
              --state-dir "$2"
          }

          seen=${lib.escapeShellArg out}
          [ -r "$seen" ] || seen=/dev/null
          names "$seen"
          # The previous file lists no group (the first run, or a conductor
          # that was never up): a trial run into /tmp, with running totals of
          # its own, finds the group first, so the dashboards never see it
          # named "Group" for one run.
          if ! grep -q '^holochain_app_info{[^}]*app_id="group#' "$seen"; then
            mkdir -p /tmp/trial-state
            if export_to /tmp/trial.prom /tmp/trial-state; then
              names /tmp/trial.prom
            fi
          fi
          export_to ${lib.escapeShellArg out} ${metricsState}
        '';
      };

      systemd.timers.moss-node-metrics = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "30s";
        };
      };

      services.holochain-services.units = {
        "moss-node.service" = {
          name = "Moss node";
          conductor = "Moss";
        };
        "moss-node-metrics.timer" = "Moss readings (timer)";
      };
    })

    (lib.mkIf cfg.dashboard.enable {
      # A second dashboard provider, next to the dashboards the Grafana module
      # ships; Grafana reads both directories.
      services.grafana.provision.dashboards.settings.providers = [
        {
          name = "holochain-moss-node";
          type = "file";
          updateIntervalSeconds = 30;
          allowUiUpdates = false;
          disableDeletion = true;
          options.path = dashboards;
        }
      ];
    })
  ];
}
