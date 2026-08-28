# Sensorica Lab fleet

The worked example behind the `nixos-holochain` modules: five Holochain edgenodes for the Sensorica Lab workshop, `edgenode-01` doubling as the Grafana monitor node, plus the live ISO participants boot from. It is its own flake so that evaluating the module repository never evaluates Sensorica's machines; copy this directory to start your own fleet.

## Layout

```
examples/sensorica-fleet/
├── flake.nix                      # inputs, the five nixosConfigurations, the ISO, the colmena hive
├── hosts/
│   ├── edgenode-01/
│   │   ├── configuration.nix      # monitor node: edgenode + Grafana/Prometheus
│   │   └── hardware-configuration.nix   # placeholder, replace per machine (below)
│   ├── edgenode-02 … 05/          # peer nodes, same shape without Grafana
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

## Operator SSH key

The hosts add the keys listed in `authorizedKeyFiles` (see `flake.nix`) to the `sensorica` user. That list reads `../../secrets/sensorica.pub` at the repository root when the file is present in the evaluated source tree; the file is gitignored, so copy `secrets/sensorica.pub.example` to `secrets/sensorica.pub` and put the real key in it. Nothing under `secrets/` other than the `.example` is ever committed.

## Deploy

```bash
# one machine
sudo nixos-rebuild switch --flake .#edgenode-01

# the whole fleet over SSH, in parallel
nix develop            # brings colmena into PATH
colmena apply --on @all
colmena apply --on edgenode-01
colmena apply --dry-run
```

## Workshop ISO

```bash
nix build .#nixosConfigurations.workshop-iso.config.system.build.isoImage
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress
sync
```
