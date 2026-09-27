{...}: {
  imports = [
    ../common.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "sensorica-holoport-01";

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
}
