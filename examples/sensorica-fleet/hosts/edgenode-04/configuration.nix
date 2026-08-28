{
  pkgs,
  authorizedKeyFiles,
  ...
}: {
  imports = [./hardware-configuration.nix];

  networking.hostName = "edgenode-04";
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

  system.stateVersion = "25.05";
}
