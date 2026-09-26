# Placeholder hardware configuration so the flake evaluates before the target
# machine exists. It describes the layout the NixOS installer's own manual
# partitioning guide creates on a UEFI machine: an ext4 root labelled `nixos`
# and a vfat ESP labelled `boot` mounted at /boot.
#
# Replace it with the output of
#   nixos-generate-config --show-hardware-config
# run on the target machine. Nothing needs keeping: that output carries
# filesystems and kernel modules, and the boot loader lives in configuration.nix.
{
  lib,
  modulesPath,
  ...
}: {
  imports = [(modulesPath + "/installer/scan/not-detected.nix")];

  # Enough to mount a SATA or NVMe root without probing the machine first.
  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "nvme"
    "usbhid"
    "sd_mod"
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = ["fmask=0077" "dmask=0077"];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
