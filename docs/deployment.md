# Deployment Guide

## Prerequisites

- NixOS on the target machine(s)
- SSH access from the deployer to each node
- Nix flakes enabled (`experimental-features = nix-command flakes` in `nix.conf`)

## Single node

On a machine already running NixOS, start from the `#minimal` template in a directory you keep under git (a flake only sees tracked files):

```bash
mkdir edgenode && cd edgenode && git init
nix flake init -t github:Sensorica/nixos-holochain#minimal

# The placeholder hardware configuration only lets the flake evaluate; replace
# it with this machine's before switching, or the next boot looks for disks by
# labels this machine may not have.
sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix

nano configuration.nix      # SSH key, hostname, hApps
git add flake.nix configuration.nix hardware-configuration.nix README.md
nix flake check --no-build
sudo nixos-rebuild switch --flake .#edgenode
```

The template boots with systemd-boot, as the NixOS installer does on UEFI; `templates/minimal/README.md` says what to change for legacy BIOS.

## Colmena prerequisites

Before running `colmena apply` from `examples/sensorica-fleet`, each host must have:

1. A real `hardware-configuration.nix` replacing the committed placeholder, generated on the target machine:
   ```bash
   sudo nixos-generate-config --show-hardware-config > examples/sensorica-fleet/hosts/edgenode-XX/hardware-configuration.nix
   ```
2. The facilitator's SSH public key in `examples/sensorica-fleet/hosts/common.nix` in the `operatorKeys` list at the top (used for the `sensorica` account and for root, which Colmena connects as; public keys are committed, a flake never sees untracked files).

## Fleet (Colmena)

```bash
cd examples/sensorica-fleet

# Deploy to all nodes in parallel (--impure: Colmena 0.4.0 cannot lock its
# `hive` input in pure mode, see examples/sensorica-fleet/README.md)
colmena apply --impure --on @all

# Deploy to a single node
colmena apply --impure --on edgenode-01

# Dry-run (shows what would change)
colmena apply --impure --dry-run
```

## Workshop ISO

```bash
# Build the ISO
nix build ./examples/sensorica-fleet#nixosConfigurations.workshop-iso.config.system.build.isoImage

# Flash to USB (replace /dev/sdX with your USB device)
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress
sync
```

## Rescuing an install from another machine

When the graphical installer fails on a machine in front of you (a Holoport, a homelab box), take it over from a laptop on the same network instead of debugging at its console. Every step below was run on 2026-09-26, rescuing a homelab install of NixOS 26.05.

### Making the USB stick

Write the ISO directly to the stick and check it byte for byte. Do not boot a NixOS 26.05 ISO through Ventoy: the initrd waits for the ISO's filesystem label (`/dev/disk/by-label/nixos-graphical-26.05-x86_64`), Ventoy never exposes it, and the boot drops to emergency mode. Ventoy's GRUB2 mode (Ctrl+R) did not help either.

```bash
sudo dd if=nixos-graphical-26.05-x86_64-linux.iso of=/dev/sdX bs=4M status=progress conv=fsync
sudo cmp -n "$(stat -c %s nixos-graphical-26.05-x86_64-linux.iso)" nixos-graphical-26.05-x86_64-linux.iso /dev/sdX && echo VERIFIED
```

`dd` returns only once `conv=fsync` has flushed everything, which on a slow stick is minutes after the copy counter reaches 100%. A red `Failed to start Load Kernel Modules` during the live boot is harmless when the boot carries on.

### Letting the laptop in

The stock installer ships an SSH server but does not start it, and its `nixos` user has no password. On the machine, in a terminal of the live session:

```bash
passwd
sudo systemctl start sshd
ip -br -4 a
```

On the laptop, with the address from the last command (it asks for that password once):

```bash
ssh-copy-id -o StrictHostKeyChecking=accept-new nixos@<machine-ip>
```

If nobody can read the address off the screen, find it from the laptop: on a home network, the installer is usually the only host answering on port 22. Replace `192.168.0` with your network's prefix.

```bash
for i in $(seq 1 254); do (timeout 1 bash -c "echo > /dev/tcp/192.168.0.$i/22" 2>/dev/null && echo 192.168.0.$i) & done; wait
```

The workshop ISO (`examples/sensorica-fleet`, `hosts/workshop-iso`) enables `services.openssh` but ships an empty `authorizedKeys` list; putting the facilitator's key there would remove the `passwd` and `ssh-copy-id` steps. Whether its sshd starts at boot has not been checked yet (the upstream installer module keeps sshd out of `multi-user.target`); tracked with the ISO work in #6.

### Reading why the installer failed

The graphical installer (Calamares) logs everything, including `nixos-install`'s output, to a root-only file:

```bash
ssh nixos@<machine-ip> 'sudo grep -a -n -E "error|onInstallationFailed|Starting job" /root/.cache/calamares/session.log | tail -30'
```

`lsblk -f` shows whether the partitions were created. A failed run leaves them mounted under `/tmp/calamares-root-*`, with swap active; the installer then offers only manual partitioning.

### Known failure: downloads fail "after 0 ms"

Symptom: `nixos-install` stops on `unable to download 'https://cache.nixos.org/…narinfo': Could not connect to server … after 0 ms`. Seen on a home router whose DNS answered the installer with an IPv6 address only (`getent ahostsv4 cache.nixos.org` empty) while the machine had no IPv6 route. Check and fix in the live session:

```bash
getent ahostsv4 cache.nixos.org
sudo nmcli con mod "Wired connection 1" ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes && sudo nmcli con up "Wired connection 1"
nix --extra-experimental-features nix-command store info --store https://cache.nixos.org
```

The last line prints `Store URL: https://cache.nixos.org` once the cache is reachable. The installed system asks the same router for DNS, so set `networking.nameservers` in its configuration (or fix the router) before its first `nixos-rebuild`.

### Retrying

Release what the failed run left behind, then relaunch the installer and choose to erase the disk:

```bash
for m in $(findmnt -rn -o TARGET | grep calamares-root | sort -r); do sudo umount "$m"; done
sudo swapoff -a
```

## Trying it without hardware

The root flake ships a single-node configuration so you can run the module on a laptop before touching a Holoport:

```bash
nixos-rebuild build-vm --flake .#minimal-vm
./result/bin/run-*-vm
# at the console (autologin as root):
systemctl is-active holochain-conductor
```

`nixos-rebuild` is absent on non-NixOS hosts (a Linux laptop with plain Nix, or a NixOS container). The same VM is reachable through the flake output it wraps:

```bash
nix build .#nixosConfigurations.minimal-vm.config.system.build.vm
./result/bin/run-*-vm
```

The flake declares the Holochain Foundation's binary cache in its `nixConfig`, but Nix only honours that with your consent. If you see

```
warning: ignoring untrusted flake configuration setting 'extra-substituters'.
Pass '--accept-flake-config' to trust it
```

then the conductor is about to be built from source, which takes hours. Pass `--accept-flake-config`, or add the substituter to your own `nix.conf`:

```
extra-substituters = https://holochain-ci.cachix.org
extra-trusted-public-keys = holochain-ci.cachix.org-1:5IUSkZc0aoRS53rfkvH9Kid40NpyjwCMCzwRTXy+QN8=
```

The first boot is not fast even so: the conductor takes a minute or more to open its admin port on a VM, and installing a hApp is slower still.

## Seeing the dashboard before deploying a fleet

`observability-vm` is the whole observability stack on one machine: an edgenode exporting its conductor's `holochain_*` series, plus Prometheus and Grafana scraping and drawing them. Grafana and Prometheus are forwarded to the host, so a real browser reaches them.

```bash
nixos-rebuild build-vm --flake .#observability-vm
./result/bin/run-observability-vm-vm
# or, on a non-NixOS host:
nix build .#nixosConfigurations.observability-vm.config.system.build.vm
./result/bin/run-observability-vm-vm
```

Then open <http://localhost:13000> (admin / workshop2026) and pick the **Holochain Fleet** dashboard; Prometheus itself is on <http://localhost:19090>. Give it a couple of minutes: the conductor needs a minute or more to come up, the metrics timer fires every 10 seconds in this VM, and the panels need a few points before they draw a line.

The dashboard panels are provisioned, not saved by hand. Editing one in the browser will appear to work and will be discarded on the next rebuild; change `modules/dashboards/holochain-fleet.json` instead.

## First boot sequence

1. NixOS boots.
2. `holochain-conductor.service` starts (waits for network). Its `preStart` generates `/var/lib/holochain/lair-passphrase` (mode 0600) if it is not already there, and the conductor reads it over `--piped`. Nothing is prompted and nothing is stored in the Nix store.
3. The unit is `Type = notify`, so it becomes active when the conductor reports readiness rather than when the process starts. On slow or unaccelerated hardware this takes a minute or more; `TimeoutStartSec` is 600s.
4. `holochain-happ-installer.service` installs and enables the configured hApps, then attaches the app WebSocket.
5. The conductor is reachable on `adminPort` (default 4444) and `appPort` (default 8888), both bound to localhost.

Every boot after the first runs the same sequence. The installer is idempotent: it skips `install-app` for apps already present, re-runs `enable-app` unconditionally, and only attaches the app WebSocket if it is not already attached. The passphrase persists in the state directory, so the keystore opens again with nobody present.

## Verifying the deployment

```bash
# Conductor status
systemctl status holochain-conductor

# Follow conductor logs
journalctl -u holochain-conductor -f

# Check hApp installer ran
systemctl status holochain-happ-installer
journalctl -u holochain-happ-installer

# Conductor metrics (metricsExporter.enable + conductorMetrics.enable)
systemctl list-timers holochain-conductor-metrics
curl -s localhost:9100/metrics | grep '^holochain_'
```

`holochain_conductor_up 0` means the timer is running and the conductor is not answering; check `journalctl -u holochain-conductor`. No `holochain_` lines at all means the timer has not fired yet, or `conductorMetrics.enable` is off.

On the monitor node:

```bash
# every configured scrape target should be "health":"up"
curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {scrapeUrl, health, lastError}'

# the provisioned dashboard should be there
# export GRAFANA_ADMIN_PASSWORD first; on a node that kept the module
# default it is the workshop password
curl -s -u "admin:$GRAFANA_ADMIN_PASSWORD" 'localhost:3000/api/search?query=Holochain'
```

## Rolling back

```bash
# Roll back to the previous NixOS generation
sudo nixos-rebuild --rollback

# List all generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```
