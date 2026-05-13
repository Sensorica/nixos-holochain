# Workshop live ISO configuration
# Boots into a KDE Plasma 6 desktop with the full dev environment pre-loaded.
# Participants can boot from USB, clone the repo, and run nixos-install.
{ config, pkgs, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-graphical-calamares-plasma6.nix"
  ];

  networking.hostName = "nixos-holochain-workshop";
  time.timeZone = "America/Montreal";

  # Workshop tooling available on the live ISO
  environment.systemPackages = with pkgs; [
    git
    kate
    konsole
    firefox
    colmena
    nixd
    nil
    alejandra
    # Convenient for participants browsing the flake
    nix-tree
  ];

  # Pre-clone the repo during ISO build so participants have it on the desktop
  # Replace with actual repo URL before building
  # system.activationScripts.cloneRepo = ''
  #   git clone https://github.com/Sensorica/nixos-holochain /home/nixos/nixos-holochain
  # '';

  services.openssh.enable = true;
  users.users.nixos.openssh.authorizedKeys.keys = [];

  system.stateVersion = "25.05";
}
