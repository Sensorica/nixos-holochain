# Deployment Guide

## Prerequisites

- NixOS on the target machine(s)
- SSH access from the deployer to each node
- Nix flakes enabled (`experimental-features = nix-command flakes` in `nix.conf`)

## Single node

```bash
git clone https://github.com/Sensorica/nixos-holochain
cd nixos-holochain

# The Sensorica fleet is the worked example; edit the host config for your machine
cd examples/sensorica-fleet
nano hosts/edgenode-01/configuration.nix

sudo nixos-rebuild switch --flake .#edgenode-01
```

## Colmena prerequisites

Before running `colmena apply` from `examples/sensorica-fleet`, each host must have:

1. A real `hardware-configuration.nix` replacing the committed placeholder, generated on the target machine:
   ```bash
   sudo nixos-generate-config --show-hardware-config > examples/sensorica-fleet/hosts/edgenode-XX/hardware-configuration.nix
   ```
2. The facilitator's SSH public key in `examples/sensorica-fleet/hosts/common.nix` under `users.users.sensorica.openssh.authorizedKeys.keys` (public keys are committed; a flake never sees untracked files).

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
