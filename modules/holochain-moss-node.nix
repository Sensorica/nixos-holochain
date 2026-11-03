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
# On the Moss 0.16 line the join needs no person: wdocker reads the password,
# the profile name and the node description from the environment and accepts an
# invite as an argument, so `inviteFile` names a root-only file holding the
# invite and a oneshot unit joins the group once and restarts the daemon (#166).
# The invite is the group's network seed and never reaches the Nix store or the
# journal. The same line points the node at a bootstrap and relay of your own
# (`bootstrapUrl`, `relayUrl`), which the Moss pilot needs because its members
# run Moss in dev mode against a server we host (#122).
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
  metrics = cfg.metrics.enable;
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

  # Joins the group the invite file names, once. The daemon creates the
  # conductor on its first start and a join needs it running, so the script
  # retries until `list-apps` answers; a group app already installed means there
  # is nothing to do, which is what makes every later start a no-op.
  #
  # wdocker prints the invite it was given and, on success, the installed app
  # (whose manifest carries the network seed), so its output goes to a private
  # file and the journal gets only a reason that cannot echo the invite.
  joinScript = pkgs.writeShellScript "moss-node-join" ''
    set -u
    PATH=${lib.makeBinPath [pkgs.coreutils pkgs.gnugrep]}
    export HOME=${stateDir}
    export WDOCKER_PASSWORD
    WDOCKER_PASSWORD=$(cat "$CREDENTIALS_DIRECTORY/password")
    ${lib.optionalString (cfg.profileName != null) "export WDOCKER_PROFILE_NAME=${lib.escapeShellArg cfg.profileName}"}
    ${lib.optionalString (cfg.nodeDescription != null) "export WDOCKER_NODE_DESCRIPTION=${lib.escapeShellArg cfg.nodeDescription}"}
    wdocker=${cfg.package}/bin/wdocker
    out=$(mktemp)
    trap 'rm -f "$out"' EXIT

    tries=0
    until "$wdocker" list-apps ${lib.escapeShellArg cfg.name} >"$out" 2>&1; do
      tries=$((tries + 1))
      if [ "$tries" -ge 60 ]; then
        echo "moss-node-join: the conductor did not answer in 10 minutes; see 'journalctl -u moss-node'" >&2
        exit 1
      fi
      sleep 10
    done

    if grep -q "installed_app_id: 'group#" "$out"; then
      echo "moss-node-join: a group is already joined; nothing to do"
      exit 0
    fi

    if "$wdocker" join-group ${lib.escapeShellArg cfg.name} "$(cat "$CREDENTIALS_DIRECTORY/invite")" >"$out" 2>&1; then
      echo "moss-node-join: joined the group; restarting the node so Moss sees it online"
      touch ${stateDir}/.restart-after-join
    else
      echo "moss-node-join: join-group failed" >&2
      # Only lines that cannot carry the invite or the seed.
      grep -oE 'invalid invite \((wrong-format|version-mismatch|invalid-seed|invalid-progenitor)\)|Failed to fetch resource|sha256 of the group happ[^,]*' "$out" >&2 || true
      echo "moss-node-join: run 'moss-node join' at a terminal to see the whole error" >&2
      exit 1
    fi
  '';

  # Root, after the join: the daemon pings Moss only for the groups present when
  # it starts. The marker outlives a failed restart, so the retry still restarts.
  restartAfterJoin = pkgs.writeShellScript "moss-node-restart-after-join" ''
    if [ -e ${stateDir}/.restart-after-join ]; then
      ${config.systemd.package}/bin/systemctl restart moss-node.service && rm -f ${stateDir}/.restart-after-join
    fi
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
        # join-group talks to the running conductor; without it, it asks every
        # question and only then fails on "No port file found".
        if ! systemctl is-active --quiet moss-node.service; then
          echo "moss-node: the node is not running; check 'moss-node logs' (is the password file written?) and join once it says 'Daemon ready.'" >&2
          exit 1
        fi
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
  # The node page's unit list, for a machine that runs this module without the
  # edgenode (the module that otherwise brings it).
  imports = [./holochain-services.nix];

  options.services.holochain-moss-node = {
    enable = lib.mkEnableOption "a Moss always-online node (wdocker's daemon) as a systemd service, with its readings";

    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        wdocker, with the Holochain binary it runs. The flake's
        `nixosModules.holochain-moss-node` defaults it to its `wdocker-0_15`
        (Moss 0.15.8, Holochain 0.6.1), the line the Sensorica group runs. The
        Moss pilot runs `wdocker-0_16` (Moss 0.16.0-rc.4 with the patched
        Holochain 0.7.1): set `package = nixos-holochain.packages.''${system}.wdocker-0_16`.
        wdocker and the group it joins must be on the same line: an invite from
        the other line is refused. Only `wdocker-0_16` honours `bootstrapUrl`
        and `relayUrl`.
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

    inviteFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/lib/secrets/moss-node-invite";
      description = ''
        A root-only file holding a Moss group invite (a link, or the bare
        `moss-<version>-...` code, with no trailing newline). When set, a
        oneshot unit joins the group once the daemon answers and restarts the
        daemon so Moss sees it online; a node that already holds a group does
        nothing, so the file is read only on the one start that joins. The
        invite carries the group's network seed: only the path reaches the Nix
        store, systemd passes the file as a credential, and the unit's output
        never prints the invite. Needs the 0.16 line, whose wdocker takes the
        profile name from the environment; on 0.15 join with `moss-node join`.

        Delete the file after the join if the machine's disk is not trusted
        with the seed; the group stays joined.
      '';
    };

    profileName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "holoport-01";
      description = "The name the node's profile takes inside the group when `inviteFile` joins it. `null` keeps wdocker's random `wdocker-xxxx`.";
    };

    nodeDescription = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "Sensorica always-online node on holoport-01";
      description = "The description shown for the node in the group when `inviteFile` joins it. `null` keeps wdocker's default.";
    };

    bootstrapUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://bootstrap.example.org";
      description = ''
        The bootstrap server the node's conductor uses, in place of Moss's
        production one. A node and the members it serves must use the same
        server or they never find each other. `null` keeps wdocker's default.
        Needs `wdocker-0_16`.
      '';
    };

    relayUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://bootstrap.example.org/relay";
      description = ''
        The iroh relay the node's conductor uses; `kitsune2-bootstrap-srv`
        serves it at `/relay` on the bootstrap's own port. `null` keeps
        wdocker's default. Needs `wdocker-0_16`.
      '';
    };

    metrics.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Write the node's readings for node_exporter (the timer below), which
        needs `services.holochain-edgenode` with its `metricsExporter`. The
        exporter asks the conductor through the edgenode's `hc`, so the
        conductor and that `hc` must be on one Holochain line: leave it on for
        the 0.15 package beside a 0.6 edgenode, and turn it off for the 0.16
        package, whose readings were not checked against any `hc` (#166).
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
          assertion = !metrics || (edge.enable && edge.metricsExporter.enable);
          message = "services.holochain-moss-node needs services.holochain-edgenode with its metricsExporter: the Moss readings go through the same exporter and textfile directory. Set services.holochain-moss-node.metrics.enable = false to run the node without them.";
        }
        {
          assertion = (cfg.bootstrapUrl == null && cfg.relayUrl == null) || (cfg.package.overridesBootstrap or false);
          message = "services.holochain-moss-node.bootstrapUrl and relayUrl need a wdocker that reads WDOCKER_BOOTSTRAP_URL and WDOCKER_RELAY_URL: set services.holochain-moss-node.package to the flake's wdocker-0_16.";
        }
        {
          assertion = cfg.inviteFile == null || (cfg.package.takesInviteFromEnvironment or false);
          message = "services.holochain-moss-node.inviteFile needs a wdocker that joins a group without a terminal (WDOCKER_PASSWORD, WDOCKER_PROFILE_NAME): set services.holochain-moss-node.package to the flake's wdocker-0_16, or join with `moss-node join`.";
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
        environment =
          {HOME = stateDir;}
          // lib.optionalAttrs (cfg.bootstrapUrl != null) {WDOCKER_BOOTSTRAP_URL = cfg.bootstrapUrl;}
          // lib.optionalAttrs (cfg.relayUrl != null) {WDOCKER_RELAY_URL = cfg.relayUrl;};
        serviceConfig = {
          User = "moss-node";
          Group = "moss-node";
          StateDirectory = "moss-node";
          StateDirectoryMode = "0700";
          WorkingDirectory = stateDir;
          LoadCredential = "password:${cfg.passwordFile}";
          # An empty password file is refused before wdaemon sees it: given an
          # empty password, wdaemon creates the conductor with it and exits 0
          # (sensorica-holoport-01, 2026-09-27).
          ExecStartPre = "${pkgs.runtimeShell} -c 'test -s \"$CREDENTIALS_DIRECTORY/password\" || { echo \"moss-node: ${cfg.passwordFile} is empty; write the conductor password into it\" >&2; exit 1; }'";
          ExecStart = "${pkgs.runtimeShell} -c 'exec ${cfg.package}/bin/wdaemon ${lib.escapeShellArg cfg.name} < \"$CREDENTIALS_DIRECTORY/password\"'";
          # An always-online node comes back whichever way the daemon ended.
          Restart = "always";
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

      services.holochain-services.units."moss-node.service" = {
        # wdocker's version, and the Holochain it brings, from the package.
        name = "Moss node";
        conductor = "Moss";
        version = lib.getVersion cfg.package;
        holochainVersion = cfg.package.holochainVersion or "";
      };
    })

    (lib.mkIf (cfg.enable && cfg.inviteFile != null) {
      # Joins the group the invite names, once. See joinScript. It runs as the
      # node's user, so the conductor and its files stay that user's; only the
      # restart after the join is root's (the `+` on ExecStartPost).
      systemd.services.moss-node-join = {
        description = "Join the Moss group of the invite file (wdocker, conductor ${cfg.name})";
        wantedBy = ["multi-user.target"];
        after = ["moss-node.service"];
        wants = ["moss-node.service"];
        serviceConfig = {
          Type = "oneshot";
          User = "moss-node";
          Group = "moss-node";
          # Both files are handed over as credentials, so a missing one fails
          # the unit with status=243/CREDENTIALS and names the path.
          LoadCredential = [
            "password:${cfg.passwordFile}"
            "invite:${cfg.inviteFile}"
          ];
          ExecStart = joinScript;
          ExecStartPost = "+${restartAfterJoin}";
          # A join that fails (no network, the conductor still starting) tries
          # again; one that has happened is a no-op.
          Restart = "on-failure";
          RestartSec = "60s";
          # Ten minutes of waiting for the conductor, plus the join.
          TimeoutStartSec = "20min";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          # The home is the state directory; the join writes the conductor's
          # config and a marker there.
          StateDirectory = "moss-node";
          StateDirectoryMode = "0700";
          WorkingDirectory = stateDir;
          UMask = "0077";
        };
      };
    })

    (lib.mkIf (cfg.enable && metrics) {
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

      services.holochain-services.units."moss-node-metrics.timer" = "Moss readings (timer)";
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
