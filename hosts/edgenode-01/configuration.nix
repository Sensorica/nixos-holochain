{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "edgenode-01";
  time.timeZone = "America/Montreal";

  services.openssh.enable = true;
  users.users.sensorica = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [ ../../secrets/sensorica.pub ];
  };

  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;

  environment.systemPackages = with pkgs; [ git kate konsole firefox ];

  services.holochain-edgenode = {
    enable      = true;
    openFirewall = true;
    metricsExporter.enable = true;
    happs = {
      windtunnel = {
        src         = ../../happs/windtunnel.happ;
        networkSeed = "workshop-2026";
      };
      moss = {
        src         = ../../happs/moss.happ;
        networkSeed = "sensorica-moss-2026";
      };
    };
  };

  # edgenode-01 acts as the monitor node: Grafana + Prometheus scrape the full fleet.
  # Access the dashboard at http://edgenode-01:3000 (admin / workshop2026).
  services.holochain-grafana = {
    enable      = true;
    openFirewall = true;
    scrapeTargets = [
      "edgenode-01:9100"
      "edgenode-02:9100"
      "edgenode-03:9100"
      "edgenode-04:9100"
      "edgenode-05:9100"
    ];
    # windtunnelTargets: uncomment once Wind Tunnel binary is wired up in Phase 1 validation
    # windtunnelTargets = [ "edgenode-01:9101" "edgenode-02:9101" ... ];
  };

  system.stateVersion = "25.05";
}
