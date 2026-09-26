# Placeholder hardware configuration so the fleet evaluates before the target
# machine exists. The disk layout is the one the nixos-holochain deployment
# runbook creates: GPT, a 1 MiB bios_grub partition, a vfat ESP labelled `boot`,
# an ext4 root labelled `nixos` and swap labelled `swap`. On a machine
# partitioned that way this file boots as written, on legacy BIOS and on UEFI.
# Replace it with the output of
#   nixos-generate-config --show-hardware-config
# run on that machine, keeping the boot.loader block below; see ../../README.md.
{
  lib,
  modulesPath,
  ...
}: {
  imports = [(modulesPath + "/installer/scan/not-detected.nix")];

  # Enough to mount a SATA or NVMe root without probing the machine first.
  # `nixos-generate-config` on the target narrows the list; nothing breaks if it
  # stays as it is.
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "ahci"
    "xhci_pci"
    "ehci_pci"
    "ohci_pci"
    "nvme"
    "sd_mod"
    "sr_mod"
  ];

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

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # `nofail` so a machine whose ESP was never created still reaches a shell
  # instead of stopping in the initrd.
  fileSystems."/efi-boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = ["nofail"];
  };

  swapDevices = [{device = "/dev/disk/by-label/swap";}];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
