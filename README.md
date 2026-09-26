# nixos-holochain

> A declarative substrate for running Holochain edgenodes, hApps, and developer environments. Built at Sensorica, intended for the Holochain community.

**Status:** the modules work and are VM-tested. A conductor and its hApps come up at boot on both supported Holochain lines (0.7.0 and 0.6.3), a fleet's traffic is on a provisioned Grafana dashboard, and an HTTP gateway serves zome reads over HTTP. Eight NixOS VM tests run in CI. What is still open is hardware: the five-machine fleet has not been deployed to real Holoports yet (issues [#8](https://github.com/Sensorica/nixos-holochain/issues/8) to [#12](https://github.com/Sensorica/nixos-holochain/issues/12)).
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

One machine:

```bash
nix flake init -t github:Sensorica/nixos-holochain#minimal
```

That writes a flake with one `nixosConfigurations.edgenode`, a `configuration.nix` to edit and a placeholder `hardware-configuration.nix` to replace with `nixos-generate-config --show-hardware-config` from the target machine. Then:

```bash
nix flake check --no-build
sudo nixos-rebuild switch --flake .#edgenode
```

A fleet of five with Grafana on the first node, a Colmena hive and a live ISO:

```bash
nix flake init -t github:Sensorica/nixos-holochain#fleet
```

To wire the modules into a flake you already have, take the input, the `holonix` follows line (the module reads its default conductor and `hc` from `inputs.holonix`) and the `specialArgs`:

```nix
{
  inputs = {
    nixos-holochain.url = "github:Sensorica/nixos-holochain";
    holonix.follows = "nixos-holochain/holonix";
  };

  outputs = inputs @ {nixpkgs, nixos-holochain, ...}: {
    nixosConfigurations.my-node = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        nixos-holochain.nixosModules.holochain-edgenode
        {
          services.holochain-edgenode = {
            enable = true;
            openFirewall = true;
            happs.my-app = {
              src = ./my-app.happ;
              networkSeed = "my-network-2026";
            };
          };
        }
      ];
    };
  };
}
```

Try it in a VM without any hardware at all:

```bash
nixos-rebuild build-vm --flake github:Sensorica/nixos-holochain#minimal-vm
./result/bin/run-*-vm

# or the observability stack, with Grafana forwarded to http://localhost:13000
nixos-rebuild build-vm --flake github:Sensorica/nixos-holochain#observability-vm
./result/bin/run-observability-vm-vm
```

See [`docs/deployment.md`](docs/deployment.md) for the deployment guide, [`docs/architecture.md`](docs/architecture.md) for how the pieces fit, and [`examples/sensorica-fleet/`](examples/sensorica-fleet/) for the worked fleet.

---

## Repository structure

```
nixos-holochain/
├── flake.nix                          # Entry point: inputs, modules, templates, packages, VM checks
├── modules/
│   ├── holochain-edgenode.nix         # Core: conductor + lair + hApp installer + metrics
│   ├── conductor-metrics.jq           # dump-network-stats → Prometheus text
│   ├── holochain-grafana.nix          # Prometheus + Grafana for a fleet
│   ├── dashboards/                    # Provisioned Grafana dashboards
│   ├── holochain-windtunnel.nix       # Opt-in: donate the machine to the Foundation's Nomad cluster
│   ├── holochain-http-gateway.nix     # HTTP gateway in front of the conductor
│   └── default.nix                    # Module aggregator
├── packages/
│   └── holochain-http-gateway.nix     # hc-http-gw build, one release per Holochain line
├── templates/
│   ├── minimal/                       # nix flake init -t …#minimal: one edgenode
│   └── fleet/                         # nix flake init -t …#fleet: five nodes, Grafana, live ISO
├── examples/
│   └── sensorica-fleet/               # The Sensorica Lab fleet: its own flake, five hosts, ISO, colmena hive
│       ├── flake.nix
│       ├── hosts/common.nix           # shared host config, operator SSH keys
│       ├── hosts/edgenode-01..05/     # configuration.nix + hardware-configuration.nix per machine
│       ├── hosts/workshop-iso/        # Live ISO for participants
│       └── README.md
├── happs/                             # .happ bundles (not committed, see happs/README.md)
├── secrets/                           # private material only, gitignored except *.example
├── workshop/
│   ├── facilitator-guide.md
│   ├── participant-handout.md
│   └── preflight-checklist.md
└── docs/
    ├── architecture.md
    ├── module-options.md              # generated by `nix build .#options-doc`
    ├── deployment.md
    ├── images/                        # dashboard screenshots
    └── archive/                       # December 2025 HolOS workshop notes
```

---

## Modules

| Module | What it does |
|--------|--------------|
| `holochain-edgenode` | Conductor with an in-process lair keystore, an idempotent hApp installer, and optional Prometheus metrics. Supports Holochain 0.7 and 0.6 from one option set. |
| `holochain-grafana` | Prometheus and Grafana on the monitor node, with the "Holochain Fleet" dashboard and its data source provisioned. |
| `holochain-http-gateway` | `hc-http-gw` in front of the conductor, exposing named zome functions over HTTP. Nothing is exposed by default. |
| `holochain-windtunnel` | Opt-in, off by default: joins the machine to the Holochain Foundation's Nomad cluster to run their Wind Tunnel scenarios. |

Key options for `services.holochain-edgenode`:

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable the edgenode |
| `package` | holonix `holochain` | Holochain conductor binary; its version selects the line |
| `hcPackage` | holonix `hc` | Holochain CLI used by the hApp installer |
| `dataDir` | `/var/lib/holochain` | Persistent state directory |
| `adminPort` | `4444` | Admin WebSocket port |
| `appPort` | `8888` | App WebSocket port |
| `happs` | `{}` | hApps to install at first boot |
| `metricsExporter.enable` | `false` | node_exporter for host metrics |
| `conductorMetrics.enable` | `false` | The conductor's own `holochain_*` series |
| `openFirewall` | `false` | Open firewall ports |

The full reference for all four modules is [`docs/module-options.md`](docs/module-options.md), generated from the declarations by `nix build .#options-doc`.

---

## Tests

Eight NixOS VM tests, all built in CI:

| Check | What it proves |
|---|---|
| `vmTest` / `vmTest-0_6` | A bare conductor comes up and answers `list-apps` on 0.7.0 and on 0.6.3 |
| `vmTestWithHapp` / `vmTestWithHapp-0_6` | A hApp installs once, stays enabled, and survives a cold boot on both lines |
| `vmTestConductorMetrics-0_6` | The conductor's gauges appear on `/metrics` on the 0.6 line |
| `vmTestGrafana` | Conductor series reach Prometheus and the dashboard is provisioned with its data source |
| `vmTestGateway` | A zome read answers 200 with JSON through the HTTP gateway, and a function outside the allow list answers 403 |
| `vmTestWindtunnel` | The generated container unit carries the flags the runner requires, and stays stopped when `autoStart = false` |

```bash
nix flake check --no-build --all-systems
nix build .#checks.x86_64-linux.vmTestGateway -L
```

---

## Workshop (mid-September 2026, Sensorica Lab)

This repo is the substrate for the Holochain NixOS workshop at Sensorica, the follow-up to the December 2025 HolOS/edgenode event. The exact date is [issue #7](https://github.com/Sensorica/nixos-holochain/issues/7).

See [`workshop/facilitator-guide.md`](workshop/facilitator-guide.md) and [`workshop/preflight-checklist.md`](workshop/preflight-checklist.md).

**Goal:** Each participant deploys a working edgenode into a 5-machine fleet, watches live P2P traffic via Grafana, and rolls back a configuration change. 4 hours, no prior Nix experience required.

---

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). In short: open an issue first, format with alejandra, every new module ships a VM test, and regenerate `docs/module-options.md` in the same commit as any option change.

---

## Roadmap

Each ticked item names the pull request that closed it.

**Phase 1: the flake evaluates and the module works**
- [x] Sensorica fleet moved to `examples/sensorica-fleet` with its own flake, so adopting the modules never evaluates Sensorica's machines (#13)
- [x] Toolchain pinned: holonix `main-0.7`, nixpkgs `nixos-25.05`, committed hardware placeholders (#13)
- [x] CI on every push and every pull request: `nix flake check` plus example-fleet evaluation (#13)
- [x] Workshop live ISO in the fleet example, cloning the repo on first boot (#13)
- [x] Colmena prerequisites documented in `docs/deployment.md` (#13)
- [x] `holochain-edgenode` drives both Holochain lines from the real admin CLI, not from documentation (#16)
- [x] hApp installer verified: installs once, stays enabled, survives a cold boot (#16)
- [x] NixOS VM tests on 0.7.0 and 0.6.3, built in CI (#16)
- [ ] Validated on a physical machine ([#8](https://github.com/Sensorica/nixos-holochain/issues/8))

**Phase 2: workshop ready**
- [x] `holochain-grafana`: Prometheus and Grafana with the "Holochain Fleet" dashboard and its data source provisioned (#17)
- [x] `conductorMetrics`: the conductor's own network stats as `holochain_*` series, on both lines (#17)
- [x] The example fleet exports metrics on all five nodes, with the Wind Tunnel runner off in writing (#17)
- [x] `holochain-windtunnel`: the Foundation's runner image, off by default, with what enabling it costs written into the option (#17)
- [x] Grafana dashboard screenshot in `docs/images/`, taken from the observability VM (#17)
- [ ] Fleet of 5 nodes tested end to end via `colmena apply` ([#11](https://github.com/Sensorica/nixos-holochain/issues/11))
- [ ] Workshop ISO boot-tested on target hardware ([#8](https://github.com/Sensorica/nixos-holochain/issues/8))
- [ ] Five Holoports with screens, keyboards and mice at the lab ([#9](https://github.com/Sensorica/nixos-holochain/issues/9))
- [ ] Dedicated router sourced and tested for P2P traffic ([#10](https://github.com/Sensorica/nixos-holochain/issues/10))
- [ ] Facilitator guide reviewed with Tibi, preflight sent seven days out ([#12](https://github.com/Sensorica/nixos-holochain/issues/12))

**Phase 3: community release**
- [x] Flake templates: `nix flake init -t …#minimal` and `#fleet` (#18)
- [x] HTTP gateway module, built from tagged source per Holochain line, VM-tested (#18)
- [x] Option reference generated from the declarations, with a CI drift check (#18)
- [x] `CONTRIBUTING.md` with the VM-test and options-doc rules (#18)
- [ ] hAppenings Community Substack announcement
- [ ] hREA module (composable with the edgenode module)
- [ ] Documentation site

**Phase 4: production hardening**
- [ ] sops-nix integration for secrets
- [ ] Lair keystore as a separate service with proper lifecycle
- [ ] Backup and restore procedures
- [ ] Conductor version upgrade paths

---

## Acknowledgements

Built at [Sensorica](https://sensorica.co), Montreal's open value network.
Successor to the December 2025 HolOS workshop organized with the Sensorica community.
