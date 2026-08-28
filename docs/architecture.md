# Architecture

## Design philosophy

The Holochain ecosystem has two deployment stories today:

1. **Dev environments via Holonix** — Nix-based, well documented, mature.
2. **Production edgenodes via HolOS** — a Buildroot-based appliance image you flash and run, not configure.

`nixos-holochain` fills the gap: a flake-based repo with reusable NixOS modules so that operators can deploy production node fleets with a single `nixos-rebuild`, without flashing a pre-built appliance image.

The architectural bet is simple. HolOS gives you a minimal Buildroot image to flash. This project takes the opposite approach: declarative NixOS configuration you own, so the community can compose Holochain with the rest of their infrastructure rather than around it.

## Module hierarchy

```
flake.nix
└── modules/
    ├── holochain-edgenode.nix     ← core: conductor + lair + hApp installer
    ├── holochain-windtunnel.nix   ← optional: Wind Tunnel scenario runner
    ├── holochain-http-gateway.nix ← optional: HTTP gateway in front of conductor
    ├── pai.nix                    ← optional: PAI per machine
    └── default.nix                ← aggregator
```

Modules are independent. Import only what you need.

## Service dependency graph

```
network-online.target
    └── holochain-conductor.service
            └── holochain-happ-installer.service (oneshot, runs once)
```

## Deployment model

The root flake ships modules only. A fleet is its own flake that takes this repository as an input; `examples/sensorica-fleet/` is the Sensorica Lab one, with a host per machine and a [Colmena](https://github.com/zhaofengli/colmena) hive:

```
cd examples/sensorica-fleet
colmena apply --on @all
```

Each node is a standard NixOS system. Colmena handles SSH-based parallel deployment. No custom daemon, no extra moving parts.

## State separation

- **Nix store** (`/nix/store`): immutable, shared, garbage collected. All binaries, configs, and scripts.
- **Data dir** (`/var/lib/holochain` by default): mutable, persistent. Conductor state, lair keystore, DHT data.

A `nixos-rebuild switch` never touches the data dir. Rollbacks are safe.

## Open questions

See GitHub issues for outstanding implementation decisions:

- Lair keystore initialization on first boot
- Secrets management for network seeds (sops-nix integration?)
- DHT data persistence across config changes
- Conductor version upgrade paths without state loss
