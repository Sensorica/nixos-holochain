{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "edgenode-02";
  time.timeZone = "America/Montreal";

  services.openssh.enable = true;
  users.users.sensorica = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    # Replace with actual authorized key before deployment
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
  };

  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;

  environment.systemPackages = with pkgs; [ git kate konsole firefox ];

  services.holochain-edgenode = {
    enable = true;
    openFirewall = true;
    happs = {
      windtunnel = {
        src = ../../happs/windtunnel.happ;
        networkSeed = "workshop-2026";
      };
      moss = {
        src = ../../happs/moss.happ;
        networkSeed = "sensorica-moss-2026";
      };
    };
  };

  system.stateVersion = "25.05";
}
