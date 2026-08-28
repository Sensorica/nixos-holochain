# The machine itself. Everything Holochain-specific is under
# `services.holochain-edgenode`; see docs/module-options.md in the module
# repository for the full option reference.
{...}: {
  imports = [./hardware-configuration.nix];

  networking.hostName = "edgenode";

  services.openssh.enable = true;

  users.users.operator = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    # Public keys are not secrets; paste your `ssh-ed25519 ...` line here
    # before deploying, or the machine has no way in over SSH.
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... operator@laptop"
    ];
  };

  services.holochain-edgenode = {
    enable = true;

    # The admin interface (4444) stays on loopback whatever this says; this
    # opens the app interface (8888) to the LAN.
    openFirewall = true;

    # hApp bundles are fetched by hash and installed once, at first boot.
    # Uncomment and point `src` at a `.happ` file or a `pkgs.fetchurl` of one.
    #
    # happs.my-app = {
    #   src = ./my-app.happ;
    #   networkSeed = "my-network-2026";
    # };
  };

  system.stateVersion = "25.05";
}
