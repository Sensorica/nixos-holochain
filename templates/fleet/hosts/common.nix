# Shared by every fleet host. Per-machine files set the hostname, import their
# hardware-configuration.nix and add roles (node-01 adds Grafana).
{pkgs, ...}: let
  # Pasted once, used for the operator account and for root below.
  operatorKeys = [
    # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... operator@laptop"
  ];
in {
  time.timeZone = "UTC";

  # The target may boot legacy BIOS or UEFI, and one tree has to serve both, so
  # the disk is GPT with a 1 MiB `bios_grub` partition *and* an ESP, and GRUB is
  # installed twice. NixOS writes the EFI half from this block; the install
  # runbook runs
  #   grub-install --target=i386-pc --boot-directory=/mnt/boot /dev/sda
  # for the BIOS half. `device = "nodev"` is what leaves that half to the
  # runbook. `efiInstallAsRemovable` writes EFI/BOOT/BOOTX64.EFI, which firmware
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

  users.users.operator = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    # Public keys are not secrets, and a flake only ever sees git-tracked
    # files, so operator keys live here rather than in an ignored file. Paste
    # your `ssh-ed25519 ...` line into `operatorKeys` above before deploying;
    # a fleet deployed with that list empty has no way in over SSH.
    openssh.authorizedKeys.keys = operatorKeys;
  };

  # Colmena connects as root by default, so the same keys go on root.
  # PermitRootLogin stays at its NixOS default, prohibit-password: keys only.
  users.users.root.openssh.authorizedKeys.keys = operatorKeys;

  # A desktop, because these nodes are meant to be sat in front of during a
  # workshop. Drop these three lines for headless servers.
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;
  environment.systemPackages = with pkgs; [git kdePackages.kate kdePackages.konsole firefox];

  services.holochain-edgenode = {
    enable = true;
    openFirewall = true;
    # node_exporter for the host series, and the conductor metrics timer for
    # the holochain_* series the fleet dashboard is built around. Every node
    # runs both; node-01 additionally scrapes and draws them.
    metricsExporter.enable = true;
    conductorMetrics.enable = true;

    # hApp bundles are fetched by hash and installed once, at first boot.
    #
    # happs.my-app = {
    #   src = ./my-app.happ;
    #   networkSeed = "my-network-2026";
    # };
  };

  # The Wind Tunnel runner is off on every node. It is not a dashboard data
  # source: it joins the machine to the Holochain Foundation's Nomad cluster
  # and runs the Foundation's scenarios, which is a donation of the machine,
  # not observability for this fleet. Turn it on per host if you mean to.
  services.holochain-windtunnel.enable = false;

  system.stateVersion = "26.05";
}
