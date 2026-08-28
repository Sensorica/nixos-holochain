# Live ISO to install the fleet from. Boots into a KDE Plasma 6 desktop with
# the Nix tooling already on PATH, so a machine can be installed without any
# further downloads.
{
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-graphical-calamares-plasma6.nix"
  ];

  networking.hostName = "nixos-holochain-live";
  time.timeZone = "UTC";

  environment.systemPackages = with pkgs; [
    git
    kdePackages.kate
    kdePackages.konsole
    firefox
    colmena
    nixd
    nil
    alejandra
    # Convenient for browsing a flake's dependency tree
    nix-tree
  ];

  # Clone the module repository on first boot, after the network is up.
  # Idempotent: skips if the directory already exists. Point it at your own
  # fleet repository if you keep one.
  systemd.services.clone-nixos-holochain = {
    description = "Clone nixos-holochain for reference on the live system";
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
