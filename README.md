# nixos-holochain

> NixOS modules for running Holochain on your own machines: a conductor with its keystore, the hApps you name installed at boot, metrics, a Grafana dashboard and an HTTP gateway, all declared in a NixOS configuration and deployed with `nixos-rebuild`.

This is for anyone who runs Holochain nodes on NixOS, or wants to: one always-on node at home, a lab or workshop fleet, a community node serving a hApp's DHT. You describe the node in Nix; the modules produce the systemd units, the conductor configuration, the lair passphrase and the idempotent hApp installer, and every change is a new NixOS generation you can roll back.

**Status:** the modules work and are VM-tested. A conductor and its hApps come up at boot on both supported Holochain lines (0.7.0 and 0.6.3), a fleet's traffic is on a provisioned Grafana dashboard, and an HTTP gateway serves zome reads over HTTP. Fourteen NixOS VM tests run in CI. What is still open is hardware: one Holoport was installed from the [runbook](docs/deployment.md#installing-on-a-holoport-legacy-bios) on 2026-09-27, and the five-machine fleet is not deployed yet (issues [#8](https://github.com/Sensorica/nixos-holochain/issues/8) to [#12](https://github.com/Sensorica/nixos-holochain/issues/12)).
**License:** [MIT](LICENSE), the license of nixpkgs, so any module here can be reused in other flakes or proposed upstream to nixpkgs as it is. The hApps these modules run keep their own licenses (Holochain itself and Moss are CAL-1.0, hREA is Apache-2.0).
**Origin:** Successor to the archived [Sensorica/holoports-workshop](https://github.com/Sensorica/holoports-workshop), pivoting from HolOS appliance-image deployment to vanilla NixOS authorship.
**Documentation:** the book at [sensorica.github.io/nixos-holochain](https://sensorica.github.io/nixos-holochain/), built from `docs/` with mdBook.

---

## Supported Holochain lines

One module set serves both lines. The version of the conductor package a node runs decides the three things that differ between them: the conductor's network section, the admin CLI prefix and the HTTP gateway release (see [`docs/architecture.md`](docs/architecture.md#two-holochain-lines-one-module)).

| Holochain | From | How a node selects it | HTTP gateway | VM tests |
|---|---|---|---|---|
| 0.7.0 | holonix `main-0.7` (input `holonix`) | the default | `hc-http-gw` 0.4.0 | `vmTest`, `vmTestWithHapp`, `vmTestGrafana`, `vmTestGateway` |
| 0.6.3 | holonix `main-0.6` (input `holonix-0_6`) | set `package` and `hcPackage` to this flake's `holochain-0_6` and `hc-0_6` | `hc-http-gw` 0.3.5 | `vmTest-0_6`, `vmTestWithHapp-0_6`, `vmTestConductorMetrics-0_6` |

`vmTestWindtunnel` runs no conductor, so it belongs to neither line. To run a node on 0.6.3, as the example fleet in [`examples/sensorica-fleet`](examples/sensorica-fleet/) does, set both packages in its `configuration.nix`, whose first line becomes `{config, pkgs, inputs, ...}:` so that `inputs` (passed by the template's `specialArgs`) and `pkgs` are in scope:

```nix
services.holochain-edgenode = {
  package = inputs.nixos-holochain.packages.${pkgs.stdenv.hostPlatform.system}.holochain-0_6;
  hcPackage = inputs.nixos-holochain.packages.${pkgs.stdenv.hostPlatform.system}.hc-0_6;
};
```

On 0.6 the admin CLI prefix changes too: check the node with `hc sandbox call --running 4444 list-apps` instead of `hc client call --port 4444 list-apps`.

---

## Why this exists

The Holochain ecosystem has two real deployment stories today:

1. **Dev environments via Holonix**: Nix-based, well documented, mature.
2. **Production edgenodes via HolOS**: a Buildroot-based appliance image you flash and run, not configure.

There is no canonical, declarative, *author it yourself* way to stand up a Holochain edgenode on commodity hardware. You either flash the HolOS pre-built image (without authoring the configuration) or you cobble together systemd units, conductor configs, and lair keystore management by hand.

`nixos-holochain` fills that gap. A flake-based repo with reusable NixOS modules so that:

- Stewards of open value networks can deploy production node fleets with a single `nixos-rebuild`.
- The Holochain community gets a reference implementation for declarative edgenode hosting.
- Workshops can teach the full stack in 4 hours instead of demoing pre-baked images.

---

## Getting started

From a freshly installed NixOS machine to a running conductor, step by step: [`docs/getting-started.md`](docs/getting-started.md).

The short version, on a machine already running NixOS with flakes enabled:

```bash
nix flake init -t github:Sensorica/nixos-holochain#minimal
```

Nix first asks whether to accept this repository's binary cache settings (four y/N questions); answering N is fine, because the first switch passes the cache explicitly (see [`docs/getting-started.md`](docs/getting-started.md#5-check-and-switch)).

That writes a flake with one `nixosConfigurations.edgenode`, a `configuration.nix` to edit and a placeholder `hardware-configuration.nix` to replace with `nixos-generate-config --show-hardware-config` from the target machine. Then:

```bash
nix flake check --no-build
sudo nixos-rebuild switch --flake .#edgenode
```

The first switch compiles Holochain from source unless it is given the Holochain Foundation's binary cache; [`docs/getting-started.md`](docs/getting-started.md) has the command that passes it.

A fleet of five with Grafana on the first node, a Colmena hive and a live ISO:

```bash
nix flake init -t github:Sensorica/nixos-holochain#fleet
```

### Pinning a version

There is no release tag yet, so every command and template here follows `main`, and your `flake.lock` pins `main` at the commit it resolved; `nix flake update nixos-holochain` moves it forward. Once `v0.1.0` is released, pin to the tag instead:

```nix
nixos-holochain.url = "github:Sensorica/nixos-holochain/v0.1.0";
```

and initialise from it with `nix flake init -t github:Sensorica/nixos-holochain/v0.1.0#minimal`. A template's `flake.nix` names `github:Sensorica/nixos-holochain` without a tag, so after initialising from a tag, set that input to the same tag.

### Adding the modules to a flake you already have

Take the input, the `holonix` follows line (the module reads its default conductor and `hc` from `inputs.holonix`) and the `specialArgs`:

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

### Trying it in a VM

No hardware at all:

```bash
nixos-rebuild build-vm --flake github:Sensorica/nixos-holochain#minimal-vm
./result/bin/run-*-vm

# or the observability stack, with Grafana forwarded to http://localhost:13000
nixos-rebuild build-vm --flake github:Sensorica/nixos-holochain#observability-vm
./result/bin/run-observability-vm-vm
```

---

## Documentation

| Where | What |
|---|---|
| [`docs/getting-started.md`](docs/getting-started.md) | A fresh NixOS machine to a running conductor with the `#minimal` template |
| [`docs/deployment.md`](docs/deployment.md) | Single node, Colmena fleet, workshop ISO, the dashboard in a VM, first boot sequence, verification, rollback |
| [`docs/architecture.md`](docs/architecture.md) | How the modules fit, the units they create, and how one module serves two Holochain lines |
| [`docs/module-options.md`](docs/module-options.md) | Every option of the four modules, generated from their declarations |
| [`templates/minimal/README.md`](templates/minimal/README.md), [`templates/fleet/README.md`](templates/fleet/README.md) | What each template contains and how to deploy it |
| [`examples/sensorica-fleet/README.md`](examples/sensorica-fleet/README.md) | A filled-in five-node example fleet |
| [`happs/README.md`](happs/README.md) | Referencing a hApp bundle by hash |
| [`workshop/`](workshop/) | Facilitator guide, participant handout and preflight checklist |

---

## Modules

| Module | What it does |
|--------|--------------|
| `holochain-edgenode` | Conductor with an in-process lair keystore, an idempotent hApp installer, and optional Prometheus metrics. Supports Holochain 0.7 and 0.6 from one option set. |
| `holochain-grafana` | Prometheus and Grafana on the monitor node, with recording rules for every state and five provisioned dashboards, each titled with its reader's question: "What is this machine running?" as Grafana's home page (each service with its state and version, each conductor with its Holochain version, each app in words), a room screen, a fleet page, a node page and an app-network page. |
| `holochain-http-gateway` | `hc-http-gw` in front of the conductor, exposing named zome functions over HTTP. Nothing is exposed by default. |
| `holochain-windtunnel` | Opt-in, off by default: joins the machine to the Holochain Foundation's Nomad cluster to run their Wind Tunnel scenarios. |
| `holochain-bootstrap` | The Kitsune2 bootstrap and relay server on your own machine, so a fleet finds itself without the Foundation's test server or the internet. See [Running your own bootstrap and relay](docs/deployment.md#running-your-own-bootstrap-and-relay). |
| `holochain-moss-node` | A Moss group's always-online node as a service, beside the edgenode, with its readings and its own Grafana page. Not part of `nixosModules.default`, because it runs a second conductor. See [`docs/moss-node.md`](docs/moss-node.md). |
| `sensorica-event-node` | The Sensorica workshop's profile layered on `holochain-edgenode`: Holochain 0.6.3, hREA, Kando and Requests & Offers on one network seed. Not part of `nixosModules.default`. See [`examples/sensorica-fleet/README.md`](examples/sensorica-fleet/README.md#holochain-line-and-happs). |

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

The full reference for `holochain-edgenode`, `holochain-grafana`, `holochain-http-gateway`, `holochain-windtunnel`, `holochain-bootstrap` and `holochain-services` (the list of services every module feeds to the dashboards) is [`docs/module-options.md`](docs/module-options.md), generated from the declarations by `nix build .#options-doc`. The Moss node's options are in [`docs/moss-node.md`](docs/moss-node.md#as-a-nixos-service); `sensorica-event-node` declares none.

---

## Tests

Fourteen NixOS VM tests, all built in CI: thirteen in the `nix flake check` job, and `vmTestHoloportInstall` in a job of its own because it copies a whole system onto a virtual disk ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

| Check | What it proves |
|---|---|
| `vmTest` / `vmTest-0_6` | A bare conductor comes up and answers `list-apps` on 0.7.0 and on 0.6.3 |
| `vmTestWithHapp` / `vmTestWithHapp-0_6` | A hApp installs once, stays enabled, and survives a cold boot on both lines, and every one of its cells has its `holochain_dht_*` series on `/metrics` |
| `vmTestConductorMetrics-0_6` | The conductor's gauges appear on `/metrics` on the 0.6 line |
| `vmTestGrafana` | Conductor and per-DHT series reach Prometheus, the five dashboards are provisioned with their data source and "What is this machine running?" is Grafana's home page, opening on this machine, every service its modules list carries its version, every panel query answers through Grafana's own query API (three are only required not to error: the two temperature panels, since a VM has no sensor, and "Same data everywhere", which needs two nodes), and the pages name a failed unit, a dead node and a stale, silent or unreadable conductor as such |
| `vmTestServices` / `vmTestServices-noBootstrap` | The node page names exactly the services the enabled modules installed, each Running; a bootstrap server frozen, stopped or failing reads Not answering, Stopped or Failed, and the room screen's tile reads "A service is down"; without the server, the same list less that one |
| `vmTestGateway` | A zome read answers 200 with JSON through the HTTP gateway, and a function outside the allow list answers 403 |
| `vmTestWindtunnel` | The generated container unit carries the flags the runner requires, and stays stopped when `autoStart = false` |
| `vmTestWdocker` | The packaged Moss `wdocker` starts its pinned Holochain 0.6.1 conductor through `wdaemon` in an offline VM, downloads nothing into its `bins` directory, and `wdocker stop` ends the conductor |
| `vmTestMossNode` | The Moss node service starts with no terminal, reads its password from a credential, survives a restart and reports `holochain_conductor_up{conductor="Moss"} 1`; with no password file it never starts, and an empty one is refused |
| `vmTestBootstrap` | Two 0.6 edgenodes with no internet find each other through a `holochain-bootstrap` server and its plain-HTTP relay; its falsifier, with one node on the wrong port, must fail |
| `vmTestHoloportInstall` | `holoport-install` lays out an empty SATA disk the ADR-017 way and installs `sensorica-holoport-01` on it; the disk then boots under SeaBIOS, which is legacy BIOS like a Holoport, with GRUB for both firmwares, the conductor active and the three workshop hApps enabled once each |

The checks without a VM are built in the same job: `edgenodeConfigRender` (`relayAllowPlainText`, `requestTimeoutS`, `dbSyncLevel` and `wasmBackend` render on each line, and that line's real conductor starts on the result), the exporter checks (`conductorMetricsJq`, `dhtMetricsJq`, `metricsHelpAgreement`, `metricsNameShape`, `edgenodeNamesWiring`), the Grafana checks (`holochainRules`, `grafanaProvisioning`, `dashboardLabels`, `dashboardWords`, `dashboardQueries`), the Moss checks (`moss-dashboard`, `moss-names`), and `edgenodeBinaryCache`, which `nix flake check` settles at evaluation.

```bash
nix flake check --no-build --all-systems
nix build .#checks.x86_64-linux.vmTestGateway -L
```

---

## Used by

Running nixos-holochain somewhere else? Open a pull request adding your deployment to this list.

---

## Repository structure

```
nixos-holochain/
├── flake.nix                          # Entry point: inputs, and the parts under nix/
├── nix/                               # One flake-parts module per family of outputs: modules, templates, packages, checks, docs
├── modules/                           # The NixOS modules, with the exporters, recording rules and dashboards they ship
├── packages/                          # hc-http-gw per Holochain line, the conductor exporter, Moss wdocker
├── templates/
│   ├── minimal/                       # nix flake init -t …#minimal: one edgenode
│   └── fleet/                         # nix flake init -t …#fleet: five nodes, Grafana, live ISO
├── examples/
│   └── sensorica-fleet/               # The Sensorica Lab fleet: its own flake, five Holoports, ISO, Colmena hive (layout in its README)
├── tests/                             # One file per check (VM tests included), with their fixtures
├── happs/                             # .happ bundles (not committed, see happs/README.md)
├── secrets/                           # private material only, gitignored except *.example
├── CHANGELOG.md                       # One section per release, published as its release note
├── scripts/
│   ├── changelog-section.sh           # Prints one version's CHANGELOG section
│   └── holoport-install.sh            # Erases one disk and installs a system that boots on a Holoport
├── workshop/
│   ├── facilitator-guide.md
│   ├── participant-handout.md
│   └── preflight-checklist.md
├── book.toml                          # The documentation book, built from docs/ with mdBook
└── docs/
    ├── introduction.md                # The book's first page; SUMMARY.md is its table of contents
    ├── architecture.md                # How the pieces fit, with every file under modules/ and packages/
    ├── module-options.md              # generated by `nix build .#options-doc`
    ├── deployment.md
    ├── moss-node.md                   # the Moss always-online node, as a service and by hand
    ├── releasing.md                   # How a maintainer cuts a release candidate and a release
    ├── adr/                           # architecture decision records, one per file
    ├── images/                        # dashboard screenshots
    └── archive/                       # December 2025 HolOS workshop notes
```

---

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). In short: open an issue first, format with alejandra, every new module ships a VM test, and regenerate `docs/module-options.md` in the same commit as any option change.

---

## Roadmap

Each ticked item names the pull request that closed it.

**Phase 1: the flake evaluates and the module works**
- [x] Sensorica fleet moved to `examples/sensorica-fleet` with its own flake, so adopting the modules never evaluates Sensorica's machines (#13)
- [x] Toolchain pinned: holonix `main-0.7`, nixpkgs `nixos-26.05` (moved from the end-of-life 25.05), committed hardware placeholders (#13)
- [x] CI on every push and every pull request: `nix flake check` plus example-fleet evaluation (#13)
- [x] Workshop live ISO in the fleet example, cloning the repo on first boot (#13)
- [x] Colmena prerequisites documented in `docs/deployment.md` (#13)
- [x] `holochain-edgenode` drives both Holochain lines from the real admin CLI, not from documentation (#16)
- [x] hApp installer verified: installs once, stays enabled, survives a cold boot (#16)
- [x] NixOS VM tests on 0.7.0 and 0.6.3, built in CI (#16)
- [ ] Validated on a physical machine ([#8](https://github.com/Sensorica/nixos-holochain/issues/8))

**Phase 2: workshop ready**
- [x] `holochain-grafana`: Prometheus and Grafana with the fleet dashboard (`holochain-fleet`) and its data source provisioned (#17)
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
- [x] Documentation site: the book at [sensorica.github.io/nixos-holochain](https://sensorica.github.io/nixos-holochain/) (#67)

**Phase 4: production hardening**
- [ ] sops-nix integration for secrets
- [ ] Lair keystore as a separate service with proper lifecycle
- [ ] Backup and restore procedures
- [ ] Conductor version upgrade paths

---

## Acknowledgements

Built at [Sensorica](https://sensorica.co), Montreal's open value network.
