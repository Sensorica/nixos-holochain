{...}: {
  imports = [
    ../common.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "edgenode-01";

  # edgenode-01 is the monitor node: Grafana + Prometheus scrape the whole
  # fleet and provision the "Holochain Fleet" dashboard at
  # http://edgenode-01:3000. `adminPassword` keeps its module default here
  # (workshop2026), which is a lab convenience, not a secret; set it before
  # putting this on a network anyone else can reach.
  services.holochain-grafana = {
    enable = true;
    openFirewall = true;
    scrapeTargets = [
      "edgenode-01:9100"
      "edgenode-02:9100"
      "edgenode-03:9100"
      "edgenode-04:9100"
      "edgenode-05:9100"
    ];
  };
}
