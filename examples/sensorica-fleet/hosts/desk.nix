# The operator desk: what a person sitting at a Sensorica Holoport sees when
# they log in as `sensorica`. One `sensorica.desktop` switch picks KDE Plasma,
# GNOME or no desktop at all; the launchers for the jobs of running the node,
# the tools the runbook uses, and an event mode that turns the screen into the
# room dashboard follow whichever desktop is picked. Self-contained on
# purpose: copy this file and the two flake inputs it needs (home-manager,
# plasma-manager) to give another NixOS machine the same kind of desk.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.sensorica;
  graphical = cfg.desktop != "none";
  plasma = cfg.desktop == "plasma";
  gnome = cfg.desktop == "gnome";
  moss = config.services.holochain-moss-node.enable or false;
  host = config.networking.hostName;
  # Grafana's home page, on this Holoport. The monitor's bare / opens it on
  # the monitor itself, so every other Holoport passes its own node.
  homePage = "${cfg.grafanaUrl}/d/holochain-home?var-node=${host}";
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

  # One Grafana entry, on the home page opened on this Holoport: it names
  # every service of this Holoport and links to the fleet, node, network and
  # Moss pages from there.
  launchers =
    [
      (launcher {
        name = "holoport-grafana";
        desktopName = "Grafana";
        comment = "What this Holoport runs, and the fleet's dashboards";
        icon = "office-chart-area";
        exec = "${firefox} --new-window \"${homePage}\"";
      })
      (launcher {
        name = "holoport-logs";
        desktopName = "Holochain logs";
        comment = "Follow the Holochain conductor's journal";
        icon = "utilities-terminal";
        exec = "${konsole} -e journalctl -f -u holochain-conductor";
      })
    ]
    ++ lib.optional moss (launcher {
      name = "holoport-moss";
      desktopName = "Moss node logs";
      comment = "Follow the Moss node's journal";
      icon = "internet-chat";
      exec = "${konsole} -e journalctl -f -u moss-node";
    })
    ++ [
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
    desktop = lib.mkOption {
      type = lib.types.enum ["plasma" "gnome" "none"];
      default = "plasma";
      description = ''
        What a person at the Holoport's screen gets. `plasma`: KDE Plasma with
        the operator panel laid out. `gnome`: GNOME with the same launchers
        as favourites. `none`: no graphical session, a text console only; the
        node and its services run the same either way.
      '';
    };

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
      need no login. Meant for the day of an event, set per host. Needs a
      desktop'';
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.eventMode.enable -> graphical;
          message = "sensorica.eventMode.enable opens the room dashboard on a desktop; set sensorica.desktop to \"plasma\" or \"gnome\".";
        }
      ];

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

      environment.systemPackages = [
        pkgs.tmux
        pkgs.btop
        inputs.holonix-0_6.packages.${pkgs.stdenv.hostPlatform.system}.hc
      ];

      # Only where Grafana runs, and only in event mode: read-only dashboards for
      # screens nobody logs in to. The admin login is unchanged.
      services.grafana.settings."auth.anonymous" = lib.mkIf (cfg.eventMode.enable && config.services.grafana.enable) {
        enabled = true;
        org_role = "Viewer";
      };
    }

    (lib.mkIf graphical {
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
          pkgs.kdePackages.kate
          pkgs.kdePackages.konsole
        ]
        ++ launchers;

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.sensorica.home.stateVersion = "26.05";
      };

      services.displayManager.autoLogin = lib.mkIf cfg.eventMode.enable {
        enable = true;
        user = "sensorica";
      };

      environment.etc."xdg/autostart/holoport-event-screen.desktop" = lib.mkIf cfg.eventMode.enable {
        source = "${eventScreen}/share/applications/holoport-event-screen.desktop";
      };
    })

    (lib.mkIf plasma {
      services.desktopManager.plasma6.enable = true;
      services.displayManager.sddm.enable = true;

      home-manager = {
        sharedModules = [inputs.plasma-manager.homeModules.plasma-manager];

        users.sensorica = {
          # The one icon on the desktop, the same Grafana home page as the
          # panel's. Plasma runs a .desktop file from ~/Desktop without asking
          # only when it is executable.
          home.file."Desktop/grafana.desktop" = {
            executable = true;
            text = ''
              [Desktop Entry]
              Type=Link
              Name=Grafana
              Comment=What this Holoport runs, on ${lib.removePrefix "http://" cfg.grafanaUrl}
              Icon=office-chart-area
              URL=${homePage}
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
                      map (l: "applications:${l.name}.desktop") launchers
                      ++ [
                        "applications:org.kde.konsole.desktop"
                        "applications:org.kde.dolphin.desktop"
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
    })

    (lib.mkIf gnome {
      services.desktopManager.gnome.enable = true;
      services.displayManager.gdm.enable = true;

      # The same launchers in the dock, and the same always-on screen as the
      # Plasma desk: no lock, no blanking, no suspend.
      home-manager.users.sensorica = {lib, ...}: {
        dconf.settings = {
          "org/gnome/shell".favorite-apps =
            map (l: "${l.name}.desktop") launchers
            ++ ["org.gnome.Console.desktop" "org.gnome.Nautilus.desktop"];
          "org/gnome/desktop/session".idle-delay = lib.hm.gvariant.mkUint32 0;
          "org/gnome/desktop/screensaver".lock-enabled = false;
          "org/gnome/settings-daemon/plugins/power".sleep-inactive-ac-type = "nothing";
        };
      };
    })
  ];
}
