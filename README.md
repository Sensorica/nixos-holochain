# nixos-holochain

> A declarative substrate for running Holochain edgenodes, hApps, and developer environments. Built at Sensorica, intended for the Holochain community.

**Status:** Pre-alpha. Workshop substrate under construction.
**License:** AGPL-3.0 (aligned with Holochain ecosystem; to be revisited when OVN License direction is clarified)
**Origin:** Successor to the archived [Sensorica/holoports-workshop](https://github.com/Sensorica/holoports-workshop), pivoting from HolOS appliance-image deployment to vanilla NixOS authorship.

---

## Why this exists

The Holochain ecosystem has two real deployment stories today:

1. **Dev environments via Holonix** — Nix-based, well documented, mature.
2. **Production edgenodes via HolOS** — a Buildroot-based appliance image you flash and run, not configure.

There is no canonical, declarative, *author it yourself* way to stand up a Holochain edgenode on commodity hardware. You either flash the HolOS pre-built image (without authoring the configuration) or you cobble together systemd units, conductor configs, and lair keystore management by hand.

`nixos-holochain` fills that gap. A flake-based repo with reusable NixOS modules so that:

- Stewards of OVNs (Sensorica, AlterNef, others) can deploy production node fleets with a single `nixos-rebuild`.
- The Holochain community gets a reference implementation for declarative edgenode hosting.
- Workshops can teach the full stack in 4 hours instead of demoing pre-baked images.

---

## Quickstart

```bash
# Add to your flake inputs
{
  inputs.nixos-holochain.url = "github:Sensorica/nixos-holochain";
}

# Import the module and enable the edgenode
{
  imports = [ inputs.nixos-holochain.nixosModules.holochain-edgenode ];

  services.holochain-edgenode = {
    enable = true;
    openFirewall = true;
    happs = {
      my-app = {
        src = ./my-app.happ;
        networkSeed = "my-network-2026";
      };
    };
  };
}
```

See [`docs/deployment.md`](docs/deployment.md) for the full deployment guide and [`examples/`](examples/) for complete working examples.

---

## Repository structure

```
nixos-holochain/
├── flake.nix                          # Entry point: inputs, outputs, fleet configs
├── modules/
│   ├── holochain-edgenode.nix         # Core: conductor + lair + hApp installer
│   ├── holochain-windtunnel.nix       # Wind Tunnel scenario runner (placeholder)
│   ├── holochain-http-gateway.nix     # HTTP gateway in front of conductor (placeholder)
│   ├── pai.nix                        # PAI per machine (placeholder)
│   └── default.nix                    # Module aggregator
├── hosts/
│   ├── edgenode-01/configuration.nix  # Fleet member 1 (Sensorica lab)
│   ├── edgenode-02 through 05/        # Fleet members 2-5
│   └── workshop-iso/configuration.nix # Live ISO for participants
├── happs/                             # .happ bundles (not committed, see happs/README.md)
├── lib/default.nix                    # Shared helper functions
├── workshop/
│   ├── facilitator-guide.md
│   ├── participant-handout.md
│   └── preflight-checklist.md
├── docs/
│   ├── architecture.md
│   ├── module-options.md
│   ├── deployment.md
│   └── archive/                       # December 2025 HolOS workshop notes
└── examples/
    ├── minimal/                       # Just a conductor, no extras
    ├── moss-group/                    # Edgenode hosting a Moss group
    └── developer-laptop/              # Full dev env (Holonix + IDE)
```

---

## Module options

See [`docs/module-options.md`](docs/module-options.md) for the full option reference.

Key options for `services.holochain-edgenode`:

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable the edgenode |
| `dataDir` | `/var/lib/holochain` | Persistent state directory |
| `adminPort` | `4444` | Admin WebSocket port |
| `appPort` | `8888` | App WebSocket port |
| `happs` | `{}` | hApps to install at first boot |
| `openFirewall` | `false` | Open firewall ports |

---

## Workshop (August 2026, Sensorica Lab)

This repo is the substrate for the August 2026 Holochain NixOS workshop at Sensorica, the follow-up to the December 2025 HolOS/edgenode event.

See [`workshop/facilitator-guide.md`](workshop/facilitator-guide.md) and [`workshop/preflight-checklist.md`](workshop/preflight-checklist.md).

**Goal:** Each participant deploys a working edgenode into a 5-machine fleet, watches live P2P traffic via Wind Tunnel + Grafana, and rolls back a configuration change. 4 hours, no prior Nix experience required.

---

## Contributing

1. Open an issue describing what you want to add or change.
2. Fork, branch from `main`, submit a PR.
3. CI must pass (`nix flake check`).
4. New modules need at least a NixOS VM test.
5. Documentation updates expected for any new public option.

---

## Roadmap

**Phase 1: Module skeleton**
- [x] Repo initialized with flake skeleton
- [ ] `holochain-edgenode` module deploys a working conductor on one machine
- [ ] First hApp (Wind Tunnel) installs at boot
- [ ] CI on every push runs `nix flake check` and a NixOS VM test

**Phase 2: Workshop ready**
- [ ] Fleet of 5 nodes deployable via `colmena apply`
- [ ] Workshop ISO boots into working dev environment
- [ ] Grafana module for observability
- [ ] Facilitator guide finalized and preflight sent

**Phase 3: Community release**
- [ ] hAppenings Community Substack announcement
- [ ] hREA module (composable with edgenode module)
- [ ] HTTP gateway module
- [ ] Documentation site

**Phase 4: Production hardening**
- [ ] sops-nix integration for secrets
- [ ] Lair keystore as separate service with proper lifecycle
- [ ] Backup and restore procedures
- [ ] Conductor version upgrade paths

---

## Acknowledgements

Built at [Sensorica](https://sensorica.co), Montreal's open value network.
Successor to the December 2025 HolOS workshop organized with the Sensorica community.
