# Shared by every fleet host. Per-machine files set the hostname, import
# their hardware-configuration.nix and add roles (sensorica-holoport-01 adds Grafana).
{pkgs, ...}: let
  # Pasted once, used for the sensorica account and for root below.
  operatorKeys = [
    # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... operator@laptop"
  ];
in {
  time.timeZone = "America/Montreal";

  # ADR-017: the Holoport is a legacy-BIOS x86_64 box, and the same tree has to
  # install on a UEFI laptop, so the disk is GPT with a 1 MiB `bios_grub`
  # partition *and* an ESP, and GRUB is installed twice. NixOS writes the EFI
  # half from this block; the install script (scripts/holoport-install.sh in
  # nixos-holochain, docs/deployment.md § "Installing on a Holoport") runs
  #   grub-install --target=i386-pc --boot-directory=/mnt/boot /dev/sda
  # for the BIOS half. `device = "nodev"` is what leaves that half to the
  # script. `efiInstallAsRemovable` writes EFI/BOOT/BOOTX64.EFI, which firmware
  # that keeps no boot variables still finds. Layout and both commands follow
  # holochain/wind-tunnel-runner (`base-install.nix`, `installer.nix`).
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # The ESP is not /boot: the BIOS GRUB keeps its own directory on the ext4 root
  # at /boot/grub, and the two must not land in the same place.
  boot.loader.efi.efiSysMountPoint = "/efi-boot";
  # The ESP itself (`/efi-boot`, label `boot`) is mounted from each host's
  # hardware-configuration.nix, which `nixos-generate-config` writes.

  services.openssh.enable = true;

  users.users.sensorica = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    # Operator public keys (ADR-012, revised): public keys are not secrets and
    # live here so every flake evaluation, nixos-rebuild and colmena apply sees
    # them. Paste your `ssh-ed25519 ...` line into `operatorKeys` at the top
    # of this file before deploying; a fleet deployed with that list empty has
    # no way in over SSH.
    openssh.authorizedKeys.keys = operatorKeys;
  };

  # Colmena connects as root by default, so the same keys go on root.
  # PermitRootLogin stays at its NixOS default, prohibit-password: keys only.
  users.users.root.openssh.authorizedKeys.keys = operatorKeys;

  # Every host's flake output carries its hostname, so one alias rebuilds
  # whichever Holoport it runs on, from the checkout the install left in
  # /root/nixos-holochain (docs/deployment.md). It does not pull: that checkout
  # carries the operator keys as a local commit, so updating it stays a
  # separate, deliberate `git -C /root/nixos-holochain pull --rebase`.
  environment.shellAliases.rebuild = "sudo nixos-rebuild switch --flake /root/nixos-holochain/examples/sensorica-fleet";

  # A Holoport is a server: it never sleeps, whoever is logged in or not.
  # Plasma's power management suspended sensorica-holoport-01 from the login
  # screen on 2026-09-27, taking the conductors and the dashboards with it.
  # With the sleep targets gone, no desktop, logind idle action or key can
  # suspend or hibernate it.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;

  environment.systemPackages = with pkgs; [git kdePackages.kate kdePackages.konsole firefox];

  services.holochain-edgenode = {
    enable = true;
    openFirewall = true;

    # Package, hApps, network seed, installer timeout and the two metrics
    # options all come from `nixosModules.sensorica-event-node` (#33), which
    # `flake.nix`'s `fleetModules` imports on every host, so the profile is
    # defined once instead of repeated here (this file used to reference its
    # own `fleetLine` and `fleetHapps` values for exactly these fields).
  };

  # The Wind Tunnel runner stays off on every fleet node (ADR-008 as amended).
  # It is not a dashboard data source: it would join the machine to the
  # Holochain Foundation's Nomad cluster and run the Foundation's scenarios,
  # which is a donation of the machine, not observability for this fleet.
  services.holochain-windtunnel.enable = false;

  system.stateVersion = "26.05";
}
