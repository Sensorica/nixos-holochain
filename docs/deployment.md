# Deployment Guide

## Prerequisites

- NixOS on the target machine(s)
- SSH access from the deployer to each node
- Nix flakes enabled (`experimental-features = nix-command flakes` in `nix.conf`)

## Single node

```bash
git clone https://github.com/Sensorica/nixos-holochain
cd nixos-holochain

# Edit the host config for your machine
nano hosts/edgenode-01/configuration.nix

sudo nixos-rebuild switch --flake .#edgenode-01
```

## Colmena prerequisites

Before running `colmena apply`, each host config must have:

1. A real `hardware-configuration.nix` — generated on the target machine:
   ```bash
   sudo nixos-generate-config --show-hardware-config > hosts/edgenode-XX/hardware-configuration.nix
   ```
2. The facilitator SSH public key committed to `secrets/sensorica.pub`:
   ```bash
   cp ~/.ssh/id_ed25519.pub secrets/sensorica.pub
   ```

Host configs already reference `../../secrets/sensorica.pub` via `authorizedKeys.keyFiles`.

## Fleet (Colmena)

```bash
# Deploy to all nodes in parallel
colmena apply --on @all

# Deploy to a single node
colmena apply --on edgenode-01

# Dry-run (shows what would change)
colmena apply --dry-run
```

## Workshop ISO

```bash
# Build the ISO
nix build .#nixosConfigurations.workshop-iso.config.system.build.isoImage

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
