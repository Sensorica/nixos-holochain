# Called from nix/checks.nix with the per-system arguments of
# nix/shared.nix.
# The Holoport install rehearsed end to end. An installer machine runs
# the holoport-install package against an empty SATA disk; the same
# disk then boots under QEMU's default firmware, SeaBIOS, which is
# legacy BIOS like the Holoport (no OVMF anywhere), and the event node
# has to come up on it with its conductor and the fleet's three hApps.
#
# One deviation from docs/deployment.md, as in nixpkgs'
# nixos/tests/installer.nix: the sandbox has no network, so the
# script gets the prebuilt system's store path instead of a flake
# reference and runs `nixos-install --system` where the doc's
# command runs `nixos-install --flake`. Everything before and after
# that one call is the documented path.
{
  holoportDisk,
  holoportInstall,
  holoportTarget,
  pkgs,
  system,
  ...
}:
pkgs.testers.nixosTest {
  name = "holoport-install";
  # The whole closure is copied onto the target disk, and three
  # hApps compile their wasm on the first boot.
  globalTimeout = 2 * 60 * 60;

  nodes.installer = {
    lib,
    modulesPath,
    ...
  }: {
    imports = ["${modulesPath}/profiles/installation-device.nix"];
    environment.systemPackages = [holoportInstall];
    virtualisation = {
      # A tmpfs root, so the only disk in this machine is the
      # Holoport's and nothing else carries a `nixos` label.
      diskImage = null;
      cores = 4;
      memorySize = 4096;
      additionalPaths = [holoportTarget.config.system.build.toplevel];
      qemu.options = holoportDisk;
    };
    nix.settings.substituters = lib.mkForce [];
    # The installer profile's empty root password next to the test
    # driver's own root password file makes NixOS warn at every
    # evaluation; the driver's shell needs neither.
    users.users.root.initialHashedPassword = lib.mkForce null;
  };

  nodes.target = {
    virtualisation = {
      # No kernel handed to QEMU and no firmware other than its
      # default: the disk's own boot code is all there is.
      useBootLoader = true;
      useDefaultFilesystems = false;
      diskImage = null;
      cores = 4;
      memorySize = 4096;
      qemu.options = holoportDisk;
      # Never used: the system that boots is the one on the disk.
      fileSystems."/" = {
        device = "/dev/disk/by-label/not-this-one";
        fsType = "ext4";
      };
    };
  };

  testScript = let
    toplevel = holoportTarget.config.system.build.toplevel;
    hc = "${holoportTarget.config.services.holochain-edgenode.hcPackage}/bin/hc";
  in ''
    import os
    import subprocess
    import tempfile

    SYSTEM = "${toplevel}"
    disk = os.path.join(tempfile.mkdtemp(), "holoport-sda.qcow2")
    subprocess.run(
        ["${pkgs.qemu_test}/bin/qemu-img", "create", "-f", "qcow2", disk, "40G"],
        check=True,
    )
    os.environ["HOLOPORT_DISK"] = disk

    installer.start()
    installer.wait_for_unit("multi-user.target")
    installer.succeed("udevadm settle")

    with subtest("the script never picks a disk by itself"):
        status, _ = installer.execute("holoport-install")
        assert status == 2, f"no arguments: expected exit 2, got {status}"
        status, _ = installer.execute(f"holoport-install {SYSTEM}")
        assert status == 2, f"one argument: expected exit 2, got {status}"
        installer.fail(f"echo /dev/sda | holoport-install /dev/sda1 {SYSTEM}")

    with subtest("a confirmation that does not name the disk erases nothing"):
        installer.fail(f"echo yes | holoport-install /dev/sda {SYSTEM}")
        parts = installer.succeed("lsblk -nro NAME /dev/sda").split()
        assert parts == ["sda"], f"the disk was touched: {parts}"

    with subtest("install"):
        installer.succeed(
            f"echo /dev/sda | holoport-install /dev/sda {SYSTEM} >&2",
            timeout=3600,
        )

    with subtest("the ADR-017 layout"):
        table = installer.succeed("${pkgs.parted}/bin/parted -s /dev/sda unit MiB print")
        installer.log(table)
        installer.succeed("${pkgs.parted}/bin/parted -s /dev/sda print | grep -E '^ 1 .*bios_grub'")
        installer.succeed("${pkgs.parted}/bin/parted -s /dev/sda print | grep -E '^ 2 .*esp'")
        for dev, label, fstype in [
            ("/dev/sda2", "boot", "vfat"),
            ("/dev/sda3", "nixos", "ext4"),
            ("/dev/sda4", "swap", "swap"),
        ]:
            got = installer.succeed(f"blkid -o value -s LABEL {dev}").strip()
            assert got == label, f"{dev}: label {got!r}, expected {label!r}"
            got = installer.succeed(f"blkid -o value -s TYPE {dev}").strip()
            assert got == fstype, f"{dev}: type {got!r}, expected {fstype!r}"

    # docs/deployment.md: sensorica-holoport-01's Grafana password file is
    # written under /mnt before the first boot.
    installer.succeed(
        "install -d -m 0700 /mnt/var/lib/secrets",
        "echo vmtest > /mnt/var/lib/secrets/grafana-admin-password",
        "chmod 0400 /mnt/var/lib/secrets/grafana-admin-password",
        "umount -R /mnt",
        "swapoff -a",
        "sync",
    )
    installer.shutdown()

    target.start()

    with subtest("SeaBIOS boots the disk through the BIOS GRUB"):
        # Without a boot sector SeaBIOS finds nothing to run and the
        # kernel never prints; this fails in minutes instead of
        # waiting out the global timeout for a shell that never comes.
        target.wait_for_console_text("Linux version", timeout=600)
        target.wait_for_unit("multi-user.target")

    with subtest("the installed system, not a test fixture"):
        assert target.succeed("hostname").strip() == "sensorica-holoport-01"
        assert target.succeed("findmnt -no SOURCE /").strip() == "/dev/sda3"
        assert target.succeed("readlink -f /run/booted-system").strip() == SYSTEM
        target.succeed("test -d /boot/grub/i386-pc")
        target.succeed("test -f /efi-boot/EFI/BOOT/BOOTX64.EFI")
        target.succeed("swapon --show=NAME --noheadings | grep -x /dev/sda4")

    with subtest("the conductor"):
        target.wait_for_unit("holochain-conductor.service", timeout=900)
        state = target.succeed("systemctl is-active holochain-conductor.service").strip()
        assert state == "active", f"expected active, got {state}"

    with subtest("the fleet's hApps are installed once and enabled"):
        target.wait_for_unit("holochain-happ-installer.service", timeout=3600)
        apps = target.succeed("${hc} sandbox call --running 4444 list-apps")
        for app in ["hrea", "kando", "requests-and-offers"]:
            key = f'"installed_app_id":"{app}"'
            assert apps.count(key) == 1, f"{app}: listed {apps.count(key)} times:\n{apps}"
        enabled = apps.count('"status":{"type":"enabled"}')
        assert enabled == 3, f"expected 3 enabled apps, got {enabled}:\n{apps}"

    with subtest("Grafana on the event node, with the password written before boot"):
        target.wait_for_unit("grafana.service")
        target.wait_for_open_port(3000)
        search = target.succeed(
            "curl -sf -u admin:vmtest 'http://localhost:3000/api/search?query=Holochain'"
        )
        assert '"uid":"holochain-fleet"' in search, search
  '';
}
