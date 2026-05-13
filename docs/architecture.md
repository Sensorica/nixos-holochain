# Architecture

## Design philosophy

The Holochain ecosystem has two deployment stories today:

1. **Dev environments via Holonix** — Nix-based, well documented, mature.
2. **Production edgenodes via HolOS** — NixOS-based but firmware-locked, opaque to the operator.

`nixos-holochain` fills the gap: a flake-based repo with reusable NixOS modules so that operators can deploy production node fleets with a single `nixos-rebuild`, without accepting a black box.

The architectural bet is simple. NixOS already won the substrate question inside HolOS. Exposing that substrate, rather than hiding it, lets the community compose Holochain with the rest of their infrastructure.

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

Fleet deployment uses [Colmena](https://github.com/zhaofengli/colmena):

```
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
