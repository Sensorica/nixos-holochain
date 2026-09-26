# Placeholder hardware configuration so the fleet evaluates before the target
# machine exists. The disk layout is the one the nixos-holochain deployment
# runbook creates: GPT, a 1 MiB bios_grub partition, a vfat ESP labelled `boot`,
# an ext4 root labelled `nixos` and swap labelled `swap`. On a machine
# partitioned that way this file boots as written, on legacy BIOS and on UEFI.
# Replace it with the output of
#   nixos-generate-config --show-hardware-config
# run on that machine, keeping nothing: the boot loader is set in hosts/common.nix, so
# replacing this file does not lose it. See ../../README.md.
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
