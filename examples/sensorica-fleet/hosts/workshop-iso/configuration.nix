# Workshop live ISO configuration
# Boots into a KDE Plasma 6 desktop with the full dev environment pre-loaded.
# Participants can boot from USB, clone the repo, and run nixos-install.
{
  config,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-graphical-calamares-plasma6.nix"
  ];

  networking.hostName = "nixos-holochain-workshop";
  time.timeZone = "America/Montreal";

  # Workshop tooling available on the live ISO
  environment.systemPackages = with pkgs; [
    git
    kdePackages.kate
    kdePackages.konsole
    firefox
    colmena
    nixd
    nil
    alejandra
    # Convenient for participants browsing the flake
    nix-tree
  ];

  # Clone the workshop repo on first boot (after network is up).
  # Idempotent: skips if the directory already exists.
  systemd.services.clone-nixos-holochain = {
    description = "Clone nixos-holochain workshop repo for participants";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "nixos";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "clone-repo" ''
        if [ ! -d /home/nixos/nixos-holochain ]; then
          ${pkgs.git}/bin/git clone \
            https://github.com/Sensorica/nixos-holochain \
            /home/nixos/nixos-holochain
        fi
      '';
    };
  };

  services.openssh.enable = true;
  users.users.nixos.openssh.authorizedKeys.keys = [];

  system.stateVersion = "25.05";
}
