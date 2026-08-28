# Sensorica Lab fleet

The worked example behind the `nixos-holochain` modules: five Holochain edgenodes for the Sensorica Lab workshop, `edgenode-01` doubling as the Grafana monitor node, plus the live ISO participants boot from. It is its own flake so that evaluating the module repository never evaluates Sensorica's machines; copy this directory to start your own fleet.

## Layout

```
examples/sensorica-fleet/
├── flake.nix                      # inputs, the five nixosConfigurations, the ISO, the colmena hive
├── hosts/
│   ├── common.nix                 # shared by every host: user, SSH keys, desktop, edgenode service
│   ├── edgenode-01/
│   │   ├── configuration.nix      # monitor node: adds Grafana/Prometheus
│   │   └── hardware-configuration.nix   # placeholder, replace per machine (below)
│   ├── edgenode-02 … 05/          # peer nodes: hostname + hardware only
│   └── workshop-iso/configuration.nix   # KDE Plasma live ISO with the repo cloned on boot
└── README.md
```

## Evaluate

```bash
cd examples/sensorica-fleet
nix flake check --no-build
nix eval .#nixosConfigurations.edgenode-01.config.system.build.toplevel.drvPath
```

The `nixos-holochain` input points at `github:Sensorica/nixos-holochain`, which is what a downstream fleet writes. From a checkout of this repository, evaluate against the checkout instead so local module changes are what gets tested:

```bash
nix flake check --no-build --override-input nixos-holochain "$(git rev-parse --show-toplevel)"
```

## Hardware configuration

Each host ships a placeholder `hardware-configuration.nix` (systemd-boot, an ext4 root labelled `nixos`, a vfat ESP labelled `boot`) so the fleet evaluates before any machine exists. Before deploying to a real Holoport, generate the real one on that machine and commit it over the placeholder:

```bash
sudo nixos-generate-config --show-hardware-config > hosts/edgenode-01/hardware-configuration.nix
```

## Operator SSH keys

Public keys are not secrets, and a flake only ever sees git-tracked files, so the operator keys are committed: paste your `ssh-ed25519 ...` line into `users.users.sensorica.openssh.authorizedKeys.keys` in `hosts/common.nix` before deploying. A fleet deployed with that list empty has no way in over SSH. Private keys, tokens and passphrases never enter git.

## Deploy

```bash
# one machine
sudo nixos-rebuild switch --flake .#edgenode-01

# the whole fleet over SSH, in parallel
nix develop            # brings colmena into PATH
colmena apply --impure --on @all
colmena apply --impure --on edgenode-01
colmena apply --impure --dry-run

# inspect the evaluated hive
colmena eval --impure -E '{nodes, ...}: nodes.edgenode-01.config.services.holochain-edgenode.enable'
```

`--impure` is required with Colmena 0.4.0 on Nix 2.25: Colmena wraps the flake as an input named `hive`, and pure mode refuses to lock it ("cannot update unlocked flake input 'hive' in pure mode"). Colmena resolves `nixos-holochain` from this directory's `flake.lock`, so `--override-input` does not reach it; bump the lock (`nix flake update nixos-holochain`) to deploy modules newer than the locked revision.

## Workshop ISO

```bash
nix build .#nixosConfigurations.workshop-iso.config.system.build.isoImage
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress
sync
```
