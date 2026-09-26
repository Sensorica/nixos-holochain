# The machine itself. Everything Holochain-specific is under
# `services.holochain-edgenode`; see docs/module-options.md in the module
# repository for the full option reference.
{config, ...}: {
  imports = [./hardware-configuration.nix];

  # The boot loader lives here rather than in hardware-configuration.nix, so
  # replacing that file with `nixos-generate-config` output does not lose it.
  # This is what the NixOS installer writes on a UEFI machine. On a legacy-BIOS
  # machine use GRUB instead:
  #   boot.loader.grub = { enable = true; device = "/dev/sda"; };
  # and see the `#fleet` template for a layout that boots both ways.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "edgenode";

  services.openssh.enable = true;

  users.users.operator = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    # Public keys are not secrets; paste your `ssh-ed25519 ...` line here
    # before deploying, or the machine has no way in over SSH. The account has
    # no password until you set one (`sudo passwd operator` on the console),
    # and sudo asks for it.
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... operator@laptop"
    ];
  };

  # `hc`, matched to the conductor's Holochain line, for talking to the admin
  # interface on the node itself: `hc client call --port 4444 list-apps`.
  environment.systemPackages = [config.services.holochain-edgenode.hcPackage];

  services.holochain-edgenode = {
    enable = true;

    # Both websockets bind to loopback and the admin port is never opened. Set
    # `openFirewall = true` to open the app port (8888) and, with
    # `metricsExporter.enable`, the node_exporter port (9100) to the LAN.

    # hApp bundles are fetched by hash and installed once, at first boot.
    # Uncomment and point `src` at a `.happ` file or a `pkgs.fetchurl` of one.
    #
    # happs.my-app = {
    #   src = ./my-app.happ;
    #   networkSeed = "my-network-2026";
    # };
  };

  system.stateVersion = "26.05";
}
