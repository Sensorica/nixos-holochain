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

## Installing on a Holoport (legacy BIOS)

A Holoport boots legacy BIOS only, so the NixOS graphical installer's default UEFI layout does not boot on it. One script, [`scripts/holoport-install.sh`](../scripts/holoport-install.sh), does the whole sequence of ADR-017: GPT with a 1 MiB `bios_grub` partition, a vfat ESP labelled `boot`, an ext4 root labelled `nixos` and 8 GiB of swap labelled `swap` at the end; root mounted at `/mnt` and the ESP at `/mnt/efi-boot`; `nixos-install`; then `grub-install --target=i386-pc` for the BIOS half. The same disk also boots on UEFI, because NixOS writes the EFI half from `hosts/common.nix`. The flake publishes the script as `packages.x86_64-linux.holoport-install` with every tool it calls pinned, and `checks.x86_64-linux.vmTestHoloportInstall` runs that package under SeaBIOS.

The script erases exactly the disk you name and nothing else. It refuses to run without one, shows that disk and the disks it will leave alone, and waits for you to type the disk's name back. It also refuses when another disk already carries one of its three labels, because the installed system mounts by label.

### The machines

| | HoloPort | HoloPort+ |
|---|---|---|
| CPU, RAM | dual-core Pentium 3.5 GHz, 8 GB | quad-core i7, 16 GB |
| Disks | 1 TB HDD at `/dev/sda` | 128 GB SSD at `/dev/sda`, 2 TB HDD at `/dev/sdb` |
| Install on | `/dev/sda` | `/dev/sda` (the SSD); `/dev/sdb` stays as it is |

Both have Ethernet and no Wi-Fi, HDMI and a USB keyboard, no DMI data, and legacy BIOS. The key for the BIOS setup is not known yet: try Del or F2; the boot menu is on F7, F8, F11 or F12.

### 1. Boot an installer and get network

Write the workshop ISO (above) or the stock NixOS 26.05 minimal ISO to a USB stick with `dd`, plug the Holoport into the lab router with Ethernet, and boot the stick from the boot menu. Then, in a root shell (`sudo -i` on either ISO):

```bash
ip -br -4 a
nix --extra-experimental-features nix-command store info --store https://cache.nixos.org
lsblk -d -o NAME,SIZE,ROTA,MODEL
```

The first line shows the address the router gave the box; the second prints `Store URL: https://cache.nixos.org` once the binary cache is reachable; the third confirms which disk is which before anything is erased.

### 2a. Install from the Holoport itself

Nearly everything is downloaded rather than built: packages come from cache.nixos.org and from the Holochain cache, which the script passes to `nixos-install` since the target has no `nix.conf` yet; only small derivations such as the unpacked Requests & Offers bundle and the configuration files are built on the box. Clone the repository, put your SSH public key in the `operatorKeys` list at the top of `examples/sensorica-fleet/hosts/common.nix`, then run the script against your checkout:

```bash
git clone https://github.com/Sensorica/nixos-holochain /root/nixos-holochain
cd /root/nixos-holochain
nano examples/sensorica-fleet/hosts/common.nix
nix --extra-experimental-features 'nix-command flakes' run --accept-flake-config .#holoport-install -- /dev/sda ./examples/sensorica-fleet#edgenode-01
```

Type `/dev/sda` when it asks. It asks once more at the end, for a root password for the console. On the base HoloPort, with its slow disk and two cores, expect this to take a while; path 2b moves the work to a laptop.

### 2b. Install from a laptop

The laptop builds the system and copies it straight onto the Holoport's new root partition over SSH, so the Holoport only partitions, receives and writes the boot loader. The laptop needs the Holochain cache in its own `nix.conf` (see [Trying it without hardware](#trying-it-without-hardware)), or it compiles the conductor.

On the laptop, from a checkout with your key already in `operatorKeys`:

```bash
nix build ./examples/sensorica-fleet#nixosConfigurations.edgenode-01.config.system.build.toplevel --out-link edgenode-01-system
```

On the Holoport, give root a password for the installer session and start its SSH server (the installer ships one but does not start it):

```bash
passwd
systemctl start sshd
```

Back on the laptop, with `HOLOPORT_IP` being the address from step 1, send your key, then start the install over SSH:

```bash
ssh-copy-id root@HOLOPORT_IP
ssh -t root@HOLOPORT_IP "nix --extra-experimental-features 'nix-command flakes' run --accept-flake-config github:Sensorica/nixos-holochain#holoport-install -- /dev/sda $(readlink -f edgenode-01-system)"
```

The script partitions the disk, sees that the system is not on the Holoport yet, prints the exact `nix copy` command and waits. Run it in a second terminal on the laptop; it has this shape:

```bash
nix copy --to "ssh://root@HOLOPORT_IP?remote-store=/mnt" "$(readlink -f edgenode-01-system)"
```

`remote-store=/mnt` writes into the new root partition rather than the installer's own store, which lives in RAM and is too small for the event node's closure (about 10 GiB, most of it the desktop). The script carries on by itself once the copy lands.

### 3. Before the first boot

`/mnt` is still mounted when the script ends. edgenode-01 runs Grafana with its admin password read from a file, which has to exist before Grafana first starts; `NEW_PASSWORD` is the one you choose:

```bash
install -d -m 0700 /mnt/var/lib/secrets
install -m 0400 /dev/null /mnt/var/lib/secrets/grafana-admin-password
printf '%s' 'NEW_PASSWORD' > /mnt/var/lib/secrets/grafana-admin-password
umount -R /mnt && swapoff -a && reboot
```

Remove the USB stick while the Holoport restarts. It boots from its disk through the BIOS GRUB.

### 4. Verify

On the Holoport, or over SSH as `sensorica` or root with the key from `operatorKeys`:

```bash
systemctl is-active holochain-conductor
systemctl status holochain-happ-installer
journalctl -u holochain-happ-installer --no-pager | grep 'Enabled app'
curl -s -u "admin:NEW_PASSWORD" 'localhost:3000/api/search?query=Holochain'
```

The first boot compiles three hApps, so `holochain-happ-installer` can take several minutes to finish on a Holoport (about a minute in the VM check). The conductor should answer `active`; the journal should end with `hc-sandbox: Enabled app: "hrea"`, `"kando"` and `"requests-and-offers"`; and the last line should return the **Holochain Fleet** dashboard, which is also at `http://HOLOPORT_IP:3000` from a laptop on the same network. [Verifying the deployment](#verifying-the-deployment) has the metrics checks.

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
