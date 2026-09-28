# ADR-017: HoloPort is a legacy-BIOS x86_64 target

- **Status:** Accepted
- **Date:** 2026-08-28
- **Source:** [#15](https://github.com/Sensorica/nixos-holochain/issues/15), issue description, section "6. Decisions (ADR amendments, effective now)"; summarised in [#1](https://github.com/Sensorica/nixos-holochain/issues/1) under "Amendments from the research record"

## Context

From #15, section 4 (HoloPort hardware, issue [#8](https://github.com/Sensorica/nixos-holochain/issues/8)):

> **Firmware boots legacy BIOS/MBR**: HolOS builds GRUB `i386-pc` only ([buildroot config](https://github.com/Holo-Host/edgenode/blob/main/holos/holos-buildroot-2025.08.config)); the 2019 HoloPortOS used GRUB on the raw disk; Holochain's runner installer partitions GPT with a `bios_grub` partition plus a vfat ESP and installs GRUB with `efiInstallAsRemovable` ([installer.nix](https://github.com/holochain/wind-tunnel-runner/blob/main/installer.nix), [base-install.nix](https://github.com/holochain/wind-tunnel-runner/blob/main/base-install.nix)). UEFI availability and Secure Boot: unknown, nothing published; check the setup screen. BIOS key: undocumented (try Del/F2, boot menu F7/F8/F11/F12).

> No DMI/SMBIOS data on the board (Holo's own detection keys on a CH340 USB-serial LED controller); disks are `/dev/sda` (+ `/dev/sdb` on the +); NIC at PCI `0000:01:00.0`; VGA framebuffer console, so HDMI + USB keyboard is the normal path.

## Decision

> Hardware stubs and the runbook (slice 5) adopt the wind-tunnel-runner layout: GPT with a 1 MiB `bios_grub` partition, a vfat ESP labelled `boot`, ext4 root labelled `nixos`, swap labelled `swap`; `boot.loader.grub` with `device = "nodev"`, `efiSupport = true`, `efiInstallAsRemovable = true`, which boots on both firmware modes. The workshop ISO stays the hybrid NixOS installer image (bootable on BIOS and UEFI). The runbook states: HDMI + USB keyboard, Ethernet only, disk `/dev/sda`, RAM 8 GB on the base model, no DMI data, BIOS keys to be found on the box. Issue #8 carries the checklist.

## Consequences

From #15, section 7, for slice 5 ([#6](https://github.com/Sensorica/nixos-holochain/issues/6)): "stub layout per ADR-017". Issue #8 was updated with the BIOS checklist.

From #15, section 8, open question: "Whether the HoloPort firmware offers UEFI or Secure Boot: only the box can answer (#8)."

## Later record

- [#21](https://github.com/Sensorica/nixos-holochain/pull/21) moved the boot loader out of the hardware stubs, because `nixos-generate-config` output never contains one: it now lives in `hosts/common.nix` of the `#fleet` template and of the example, so the stubs describe filesystems only. The `#minimal` template targets a stock NixOS UEFI install with systemd-boot, and a comment in its `configuration.nix` gives the GRUB lines for legacy BIOS. The Holoport layout of this ADR stays with `#fleet` and the example.
- [#61](https://github.com/Sensorica/nixos-holochain/pull/61) wrote the install sequence of this decision as one script, `scripts/holoport-install.sh`, published as `packages.x86_64-linux.holoport-install`: the layout above with 8 GiB of swap at the end of the disk, `nixos-install`, then `grub-install --target=i386-pc` for the BIOS half, while NixOS writes the EFI half from `hosts/common.nix`. `checks.x86_64-linux.vmTestHoloportInstall` runs it on an empty SATA disk and boots that disk under SeaBIOS, which is legacy BIOS like the Holoport. The runbook is [docs/deployment.md § Installing on a Holoport (legacy BIOS)](../deployment.md#installing-on-a-holoport-legacy-bios).
- The first install on a real Holoport, `sensorica-holoport-01` on 2026-09-27, came into `main` with [#67](https://github.com/Sensorica/nixos-holochain/pull/67). The runbook records what it showed: Esc at power-on opens the base HoloPort's firmware boot menu, its live system reads the stick reliably only from a USB 2 port, and a graphical desktop freezes on its Intel HD 610. The BIOS setup key, and whether UEFI or Secure Boot exist, are still unknown, so the open question above stands and issue #8 is open.
