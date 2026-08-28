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

## First boot sequence

1. NixOS boots
2. `holochain-conductor.service` starts (waits for network)
3. `holochain-happ-installer.service` runs once, installs configured hApps
4. Conductor is reachable on `adminPort` (default: 4444) and `appPort` (default: 8888)

## Verifying the deployment

```bash
# Conductor status
systemctl status holochain-conductor

# Follow conductor logs
journalctl -u holochain-conductor -f

# Check hApp installer ran
systemctl status holochain-happ-installer
journalctl -u holochain-happ-installer
```

## Rolling back

```bash
# Roll back to the previous NixOS generation
sudo nixos-rebuild --rollback

# List all generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```
