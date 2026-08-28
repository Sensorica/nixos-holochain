{...}: {
  imports = [
    ../common.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "node-01";

  # node-01 is the monitor node: Grafana and Prometheus scrape the whole fleet
  # and provision the "Holochain Fleet" dashboard at http://node-01:3000.
  # `adminPassword` keeps its module default here (workshop2026), which is a
  # lab convenience, not a secret; set it before putting this on a network
  # anyone else can reach.
  services.holochain-grafana = {
    enable = true;
    openFirewall = true;
    scrapeTargets = [
      "node-01:9100"
      "node-02:9100"
      "node-03:9100"
      "node-04:9100"
      "node-05:9100"
    ];
  };
}
