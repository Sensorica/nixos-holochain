#!/usr/bin/env bash
# holoport-install: erase one disk, lay it out the ADR-017 way, install a NixOS
# system on it and make it boot on legacy BIOS (a Holoport) as well as UEFI.
#
# This file is the single source of the install sequence. The flake exposes it
# as `packages.x86_64-linux.holoport-install` with every tool it calls pinned,
# docs/deployment.md § "Installing on a Holoport (legacy BIOS)" runs that, and
# `checks.x86_64-linux.vmTestHoloportInstall` runs the same package under
# SeaBIOS. Layout and commands follow holochain/wind-tunnel-runner
# (`installer.nix`, `base-install.nix`).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: holoport-install DISK SOURCE

  DISK    the whole disk to erase, for example /dev/sda. Never guessed: a
          HoloPort+ has two disks, and this erases the one you name.
  SOURCE  what to install, either
            a flake reference ending in #<host>, built on this machine with
            the Holochain binary cache, for example
            github:Sensorica/nixos-holochain?dir=examples/sensorica-fleet#sensorica-holoport-01
          or
            a /nix/store/...-nixos-system-* path built elsewhere. If it is not
            in this machine's store, the script prints the `nix copy` command
            to run on the machine that built it and waits for the copy.

Layout (GPT): 1 MiB bios_grub, 510 MiB vfat ESP labelled `boot`, ext4 root
labelled `nixos`, swap labelled `swap` (SWAP_SIZE, default 8GiB) at the end.
Root is mounted at /mnt and the ESP at /mnt/efi-boot, then nixos-install, then
`grub-install --target=i386-pc` for the BIOS half. /mnt stays mounted so files
the system needs before its first boot can be written under it.
EOF
}

die() {
  echo "holoport-install: $*" >&2
  exit 1
}

if [ "$#" -ne 2 ]; then
  usage >&2
  exit 2
fi

# A /dev/disk/by-id/... link resolves to its /dev/sdX node, so partition names
# and the label check below compare kernel names.
disk=$(readlink -f "$1")
source=$2
swap_size=${SWAP_SIZE:-8GiB}

holochain_cache=(
  --option extra-substituters https://holochain-ci.cachix.org
  --option extra-trusted-public-keys holochain-ci.cachix.org-1:5IUSkZc0aoRS53rfkvH9Kid40NpyjwCMCzwRTXy+QN8=
)

[ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
[ -b "$disk" ] || die "$disk is not a block device"
[ "$(lsblk -dno TYPE "$disk")" = disk ] || die "$disk is not a whole disk; name the disk, not a partition"

case $source in
  /nix/store/*) mode=system ;;
  *'#'?*) mode=flake ;;
  *) die "SOURCE must be a flake reference ending in #<host> or a /nix/store path to a built system, not '$source'" ;;
esac

if lsblk -nro MOUNTPOINTS "$disk" | grep -q .; then
  die "something on $disk is mounted or in use as swap; this is not the disk to erase, or release it first"
fi
if mountpoint -q /mnt; then
  die "/mnt is already a mount point; unmount it first (umount -R /mnt)"
fi

# The installed system mounts by label, so a second disk that already carries
# one of these labels (a HoloPort+ whose other disk held an earlier install)
# would make the first boot pick between two roots.
for label in nixos boot swap; do
  while read -r dev; do
    [ -n "$dev" ] || continue
    [ "$dev" = "$disk" ] && continue
    [ "/dev/$(lsblk -no PKNAME "$dev")" = "$disk" ] && continue
    die "$dev, outside $disk, is labelled '$label' and would clash with the new install; wipe it first (wipefs -a $dev)"
  done < <(blkid -c /dev/null -t "LABEL=$label" -o device || true)
done

part() {
  case $disk in
    *[0-9]) echo "${disk}p$1" ;;
    *) echo "$disk$1" ;;
  esac
}

echo "This ERASES everything on $disk:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MODEL,SERIAL "$disk"
echo
echo "Disks left untouched:"
lsblk -dno NAME,SIZE,MODEL | grep -v "^$(basename "$disk") " || echo "  (none)"
echo
printf 'Type %s to erase it and install %s: ' "$disk" "$source"
read -r answer || true
[ "$answer" = "$disk" ] || die "answer did not match $disk; nothing was changed"

echo "==> partitioning $disk"
wipefs -a "$disk"
parted -s "$disk" -- mklabel gpt \
  mkpart bios 1MiB 2MiB \
  set 1 bios_grub on \
  mkpart boot fat32 2MiB 512MiB \
  set 2 esp on \
  mkpart nixos ext4 512MiB "-$swap_size" \
  mkpart swap linux-swap "-$swap_size" 100%
udevadm settle
for n in 2 3 4; do
  for _ in $(seq 30); do
    [ -b "$(part "$n")" ] && break
    sleep 1
  done
  [ -b "$(part "$n")" ] || die "$(part "$n") did not appear after partitioning"
done

echo "==> formatting"
mkfs.fat -F 32 -n boot "$(part 2)"
mkfs.ext4 -F -L nixos "$(part 3)"
mkswap -L swap "$(part 4)"
# Let udev finish probing the new filesystems before mounting; without this a
# VM run once failed here with "wrong fs type".
udevadm settle

echo "==> mounting"
mkdir -p /mnt
mount -t ext4 "$(part 3)" /mnt
mkdir -p /mnt/efi-boot
mount -o umask=077 "$(part 2)" /mnt/efi-boot
swapon "$(part 4)"

echo "==> installing $source"
if [ "$mode" = flake ]; then
  # The target has no nix.conf yet, so the Holochain cache is passed here or
  # the conductor is compiled from source on the machine.
  nixos-install --no-channel-copy "${holochain_cache[@]}" --flake "$source"
else
  if ! nix-store --check-validity "$source" 2>/dev/null &&
    ! nix-store --store /mnt --check-validity "$source" 2>/dev/null; then
    address=$(ip -4 -o addr show scope global | awk '{ sub(/\/.*/, "", $4); print $4; exit }')
    echo "$source is not in this machine's store. On the machine that built it, run:"
    echo
    echo "  nix copy --to 'ssh://root@${address:-<this-machine>}?remote-store=/mnt' $source"
    echo
    echo "Waiting for the copy to land in /mnt (Ctrl-C to stop; /mnt stays mounted)..."
    until nix-store --store /mnt --check-validity "$source" 2>/dev/null; do
      sleep 10
    done
  fi
  nixos-install --no-channel-copy --system "$source"
fi

# NixOS installs the UEFI half (device = "nodev", efiInstallAsRemovable) during
# nixos-install; the BIOS half has to be written by hand, once, into the MBR and
# the bios_grub partition. Its modules live in /boot/grub on the ext4 root, next
# to the grub.cfg NixOS regenerates on every switch.
echo "==> installing GRUB for legacy BIOS"
grub-install --target=i386-pc --boot-directory=/mnt/boot "$disk"

echo
echo "Installed on $disk. /mnt is still mounted: write anything the system needs before its first boot under /mnt now, then run"
echo "  umount -R /mnt && swapoff $(part 4) && reboot"
