{...}: {
  imports = [
    ../common.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "edgenode-01";

  # edgenode-01 is the monitor node: Grafana + Prometheus scrape the whole fleet.
  # Dashboard at http://edgenode-01:3000 (admin / workshop2026).
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
    # windtunnelTargets: slice 3 wires the Wind Tunnel runner (ADR-008).
  };
}
