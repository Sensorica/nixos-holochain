# The operator desk: what a person sitting at a Sensorica Holoport sees when
# they log in as `sensorica`. Five launchers for the jobs of running the node,
# a laid-out Plasma session declared through plasma-manager, the tools the
# runbook uses, and an event mode that turns the screen into the room
# dashboard. Self-contained on purpose: copy this file and the two flake
# inputs it needs (home-manager, plasma-manager) to give another NixOS machine
# the same kind of desk.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.sensorica;
  host = config.networking.hostName;
  konsole = "${pkgs.kdePackages.konsole}/bin/konsole";
  firefox = "${config.programs.firefox.package}/bin/firefox";

  launcher = {
    name,
    desktopName,
    comment,
    icon,
    exec,
  }:
    pkgs.makeDesktopItem {
      inherit name desktopName comment icon exec;
      categories = ["System"];
    };

  launchers = [
    (launcher {
      name = "holoport-fleet";
      desktopName = "Fleet dashboard";
      comment = "Which Holochain node needs attention, across the whole fleet";
      icon = "office-chart-area";
      exec = "${firefox} --new-window \"${cfg.grafanaUrl}/d/holochain-fleet\"";
    })
    (launcher {
      name = "holoport-node";
      desktopName = "This node";
      comment = "Is this Holoport working, app by app";
      icon = "computer";
      exec = "${firefox} --new-window \"${cfg.grafanaUrl}/d/holochain-node?var-node=${host}\"";
    })
    (launcher {
      name = "holoport-logs";
      desktopName = "Holochain logs";
      comment = "Follow the Holochain conductor's journal";
      icon = "utilities-terminal";
      exec = "${konsole} -e journalctl -f -u holochain-conductor";
    })
    (launcher {
      name = "holoport-moss";
      desktopName = "Moss node";
      comment = "Attach to the Moss node's tmux session, or open it";
      icon = "internet-chat";
      exec = "${konsole} -e ${pkgs.tmux}/bin/tmux new-session -A -s moss";
    })
    (launcher {
      name = "holoport-rebuild";
      desktopName = "Rebuild";
      comment = "Apply this Holoport's configuration from /etc/nixos-holochain";
      icon = "system-software-update";
      exec = "${konsole} --hold -e sudo nixos-rebuild switch --flake /etc/nixos-holochain/examples/sensorica-fleet";
    })
  ];

  eventScreen = pkgs.makeDesktopItem {
    name = "holoport-event-screen";
    desktopName = "Event screen";
    comment = "The room dashboard, full screen";
    icon = "office-chart-area";
    exec = "${firefox} --kiosk \"${cfg.grafanaUrl}/d/holochain-now?kiosk\"";
  };
in {
  options.sensorica = {
    grafanaUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://sensorica-holoport-01.local:3000";
      description = ''
        The monitor node's Grafana, as every Holoport's browser reaches it. The
        `.local` name comes from the Avahi responder each Holoport runs, so it
        needs no DNS on the lab network.
      '';
    };

    eventMode.enable = lib.mkEnableOption ''
      event mode: log `sensorica` in without a password and open the room
      dashboard full screen at every boot. On the monitor node it also lets
      Grafana show dashboards to anonymous viewers (read-only), so the screens
      need no login. Meant for the day of an event, set per host'';
  };

  config = {
    # Lets `sensorica-holoport-01.local` resolve on every Holoport and laptop in
    # the lab without a DNS server.
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
      };
    };

    programs.firefox = {
      enable = true;
      # A kiosk screen must not open on a welcome tab or a default-browser prompt.
      policies = {
        DontCheckDefaultBrowser = true;
        DisableTelemetry = true;
        OverrideFirstRunPage = "";
        OverridePostUpdatePage = "";
      };
    };

    environment.systemPackages =
      [
        pkgs.tmux
        pkgs.btop
        inputs.holonix-0_6.packages.${pkgs.stdenv.hostPlatform.system}.hc
      ]
      ++ launchers;

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      sharedModules = [inputs.plasma-manager.homeModules.plasma-manager];

      users.sensorica = {
        home.stateVersion = "26.05";

        # An icon on the desktop that opens the fleet's Grafana home. Plasma
        # runs a .desktop file from ~/Desktop without asking only when it is
        # executable.
        home.file."Desktop/grafana.desktop" = {
          executable = true;
          text = ''
            [Desktop Entry]
            Type=Link
            Name=Grafana
            Comment=The fleet's dashboards on ${lib.removePrefix "http://" cfg.grafanaUrl}
            Icon=office-chart-area
            URL=${cfg.grafanaUrl}/
          '';
        };

        programs.plasma = {
          enable = true;
          workspace.lookAndFeel = "org.kde.breezedark.desktop";

          # An operator desk and an event screen both stay on; nobody should
          # come back to a lock screen or a sleeping machine.
          kscreenlocker = {
            autoLock = false;
            lockOnResume = false;
          };
          powerdevil.AC = {
            autoSuspend.action = "nothing";
            turnOffDisplay.idleTimeout = "never";
          };

          panels = [
            {
              location = "bottom";
              height = 44;
              # sensorica-holoport-01 drives two screens; the desk is on both.
              screen = "all";
              widgets = [
                "org.kde.plasma.kickoff"
                {
                  iconTasks.launchers =
                    map (l: "applications:${l.name}") launchers
                    ++ [
                      "applications:org.kde.konsole.desktop"
                      "applications:org.kde.dolphin.desktop"
                      "applications:firefox.desktop"
                    ];
                }
                "org.kde.plasma.marginsseparator"
                {
                  systemMonitor = {
                    title = "This Holoport";
                    displayStyle = "org.kde.ksysguard.linechart";
                    sensors = [
                      {
                        name = "cpu/all/usage";
                        color = "61,174,233";
                        label = "CPU %";
                      }
                      {
                        name = "memory/physical/usedPercent";
                        color = "246,116,0";
                        label = "RAM %";
                      }
                    ];
                  };
                }
                "org.kde.plasma.systemtray"
                "org.kde.plasma.digitalclock"
              ];
            }
          ];
        };
      };
    };

    services.displayManager.autoLogin = lib.mkIf cfg.eventMode.enable {
      enable = true;
      user = "sensorica";
    };

    environment.etc."xdg/autostart/holoport-event-screen.desktop" = lib.mkIf cfg.eventMode.enable {
      source = "${eventScreen}/share/applications/holoport-event-screen.desktop";
    };

    # Only where Grafana runs, and only in event mode: read-only dashboards for
    # screens nobody logs in to. The admin login is unchanged.
    services.grafana.settings."auth.anonymous" = lib.mkIf (cfg.eventMode.enable && config.services.grafana.enable) {
      enabled = true;
      org_role = "Viewer";
    };
  };
}
