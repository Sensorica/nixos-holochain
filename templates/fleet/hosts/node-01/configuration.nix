{...}: {
  imports = [
    ../common.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "node-01";

  # node-01 is the monitor node: Grafana and Prometheus scrape the whole fleet
  # and provision the "Holochain Fleet" dashboard at http://node-01:3000. The
  # firewall is open, so the admin password is read from a file on the node
  # instead of the module default, which would sit world-readable in the Nix
  # store. Create the file before the first `colmena apply`;
  # `adminPasswordFile` in docs/module-options.md gives the exact commands.
  services.holochain-grafana = {
    enable = true;
    openFirewall = true;
    adminPasswordFile = "/var/lib/secrets/grafana-admin-password";
    scrapeTargets = [
      "node-01:9100"
      "node-02:9100"
      "node-03:9100"
      "node-04:9100"
      "node-05:9100"
    ];
  };
}
