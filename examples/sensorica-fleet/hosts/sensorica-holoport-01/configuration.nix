{...}: {
  imports = [
    ../common.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "sensorica-holoport-01";

  # Switches for this Holoport. Change one, save, then run `rebuild`; each
  # generation stays in the boot menu, so a switch that goes wrong is undone
  # with `sudo nixos-rebuild switch --rollback`.
  sensorica.desktop = "plasma"; # "plasma" (KDE), "gnome" or "none" (text console only)
  sensorica.eventMode.enable = false; # true: no login, the room dashboard full screen at boot
  services.holochain-edgenode.enable = true; # false: no Holochain conductor, no hApps
  sensorica.remoteAccess.enable = false; # true once Headscale runs and the key is in /var/lib/secrets/headscale-authkey

  # sensorica-holoport-01 is the monitor node: Grafana + Prometheus scrape the whole
  # fleet and provision the "Holochain Fleet" dashboard at
  # http://sensorica-holoport-01:3000. The firewall is open, so the admin password is
  # read from a file on the node instead of the module default, which would
  # sit world-readable in the Nix store. Create the file before the first
  # `colmena apply`; `adminPasswordFile` in docs/module-options.md gives the
  # exact commands.
  services.holochain-grafana = {
    enable = true;
    openFirewall = true;
    adminPasswordFile = "/var/lib/secrets/grafana-admin-password";
    scrapeTargets = [
      "sensorica-holoport-01:9100"
      "sensorica-holoport-02:9100"
      "sensorica-holoport-03:9100"
      "sensorica-holoport-04:9100"
      "sensorica-holoport-05:9100"
    ];
  };

  # The fleet's admin plane (docs/admin-plane.md): Headscale at hs.sensorica.co
  # and Grafana at grafana.sensorica.co, behind nginx with Let's Encrypt. The
  # lab router forwards TCP 80 and 443 here and nothing else. Both names are
  # fixed A records at GoDaddy, whose API is closed to small accounts, so the
  # drift check publishes admin_plane_dns_matches_public_ip and a change of
  # the lab's IP is fixed by hand in GoDaddy. Grafana's login is the only gate
  # on the public name: its admin password file above must hold a strong one.
  services.admin-plane = {
    enable = true;
    headscale = {
      domain = "hs.sensorica.co";
      baseDomain = "sensorica.internal";
    };
    grafana.domain = "grafana.sensorica.co";
  };

  # The Sensorica Moss group's always-online node (docs/moss-node.md). Two
  # steps per machine, once: write the conductor password to the file below
  # (root-only, no trailing newline), then `sudo moss-node join "INVITE_LINK"`
  # with an invite from the Sensorica group in Moss.
  services.holochain-moss-node = {
    enable = true;
    name = "sensorica";
    passwordFile = "/var/lib/secrets/moss-node-password";
    group = "Sensorica";
    dashboard.title = "Is the Sensorica group always online?";
    # The two Vines chats of the Sensorica group, by the tail of their
    # installed_app_id, as the homelab's Moss node listed them on 2026-09-27
    # (athanor 539e648). The names members gave them in Moss are not known
    # yet, so both keep the exporter's own numbering; listing them makes each
    # expected, so it reads "Not running" if this node stops holding it.
    appletNames = {
      "applet#uhc$e$k1h2cpht$kfgs$v$l$t$3zhz-b$d_b$t$5kq$lyybe$vs$6lb$xzzsgd$hu$5ry$" = "Vines 1";
      "applet#uhc$e$krun4ink$1nl$paibamp$j$j3r$t$egt$57b$rc$ue$c$2j$bd$1a$k$hbh$g$p$zu$l$" = "Vines 2";
    };
  };
}
