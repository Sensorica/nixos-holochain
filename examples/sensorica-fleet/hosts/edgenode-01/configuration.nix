{
  pkgs,
  authorizedKeyFiles,
  ...
}: {
  imports = [./hardware-configuration.nix];

  networking.hostName = "edgenode-01";
  time.timeZone = "America/Montreal";

  services.openssh.enable = true;
  users.users.sensorica = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keyFiles = authorizedKeyFiles;
  };

  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;

  environment.systemPackages = with pkgs; [git kdePackages.kate kdePackages.konsole firefox];

  # hApps are installed at boot from bundles fetched by hash; slice 2 adds them (ADR-006, ADR-012).
  services.holochain-edgenode = {
    enable = true;
    openFirewall = true;
    metricsExporter.enable = true;
  };

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

  system.stateVersion = "25.05";
}
