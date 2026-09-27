# Changelog

All notable changes to nixos-holochain are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) on the flake's public surface: module option names and defaults, flake outputs (`nixosModules.*`, `templates.*`, `packages.*`), and dashboard uids.

Below 1.0.0, a minor version may break that surface. Every such change is listed first in its version, under `### Breaking`, with what to change in a configuration that used the old form. The other headings are the standard ones, in this order when present: Added, Changed, Deprecated, Removed, Fixed, Security.

Every tag has its own section, release candidates included, and the release workflow publishes that section as the GitHub release note. How to cut a release: [`docs/releasing.md`](docs/releasing.md).

## [Unreleased]

Nothing has been released yet. This section records what `main` holds after the September 2026 stack (#13, #16 to #21, #23), compared with the May 2026 tree (`aa7a5a8`) that anyone following `main` before it had.

### Breaking

- The Sensorica fleet is no longer part of the root flake. The five hosts, the workshop ISO and the Colmena hive live in `examples/sensorica-fleet/`, a flake of its own that takes this repository as an input; the root `nixosConfigurations` holds only `minimal-vm` and `observability-vm`, and there is no root `colmena` output. (#13)
- nixpkgs is pinned to `nixos-26.05` instead of following `nixos-unstable`, and holonix to `main-0.7`, so the default conductor is Holochain 0.7.0. (#13, #20)
- `services.holochain-edgenode.bootstrapUrl` and `signalUrl` default to `null` instead of `https://bootstrap.holo.host` and `wss://signal.holo.host`. `null` resolves to `https://dev-test-bootstrap2.holochain.org` for the bootstrap server (with a trailing slash from 0.7) and, below 0.7, to `wss://dev-test-bootstrap2.holochain.org` for signalling. From 0.7 `signalUrl` is ignored with a warning; use `relayUrl`. A node that kept the old defaults moves to a different bootstrap server on upgrade, so a fleet that must keep peering with nodes still on the old defaults has to set `bootstrapUrl` explicitly. (#16)
- `nixosModules.pai` and `modules/pai.nix` are removed. (#18)
- `services.holochain-http-gateway` is a new module under the old name: `listenPort` and `conductorAppPort` are gone, and the gateway listens on `address` (default `127.0.0.1`) and `port` (default `8090`) and serves only the apps and functions named in `allowedAppIds` and `allowedFns`. (#18)
- `examples/minimal`, `examples/moss-group` and `examples/developer-laptop` are removed; `nix flake init -t github:Sensorica/nixos-holochain#minimal` replaces the first. (#18)
- `services.holochain-grafana.windtunnelTargets` is removed: the Wind Tunnel runner exposes nothing to scrape. (#17)
- `services.holochain-windtunnel` is rewritten, and its options `conductorAdminPort` and `metricsPort` are removed. The old module was a placeholder that only raised a warning, so no behaviour is lost, but a configuration that sets either option no longer evaluates. (#17)
- `services.holochain-edgenode.openFirewall` no longer opens the admin port, and `allowedOrigins` now governs the app interface only. The admin interface takes its origins from the new `adminAllowedOrigins`, default `holochain_websocket`. A configuration that reached the admin API from another machine or from a browser has to open that path explicitly. (#21)
- `services.holochain-edgenode.dataDir` must be under `/var/lib/`; an assertion rejects any other path. (#21)

### Added

- `holochain-edgenode` installs and enables the hApps in `happs` at boot through the real admin CLI, on Holochain 0.7.0 (`hc client call`) and 0.6.3 (`hc sandbox call`), from one option set. The installer is idempotent and verifies each outcome from `list-apps`. New options: `relayUrl`, `installerTimeout`, `passphraseFileName`, `useSystemdNotify`. (#16)
- `packages.<system>.holochain-0_6` and `hc-0_6`, for fleets on the 0.6 line. (#16)
- `services.holochain-edgenode.conductorMetrics`: ten `holochain_conductor_*` series from the conductor's own `dump-network-stats`, written for node_exporter's textfile collector on both lines, with `metricsExporter.textfileDirectory`. (#17)
- `holochain-grafana` provisions the Prometheus data source and the `Holochain Fleet` dashboard (uid `holochain-fleet`), with the options `dashboards`, `scrapeInterval` (default 15 s), `adminUser` and `adminPassword`. (#17)
- `holochain-windtunnel`, formerly a placeholder, now runs the Holochain Foundation's Wind Tunnel runner image, pinned by digest and off by default; its description states what enabling it gives away. (#17)
- `holochain-http-gateway` builds `hc-http-gw` from tagged source per Holochain line (v0.4.0 for 0.7, v0.3.5 for 0.6), exposed as `packages.<system>.holochain-http-gateway` and `holochain-http-gateway-0_6`. (#18)
- Flake templates `minimal` (also `default`) and `fleet`. (#18)
- `packages.<system>.options-doc`, which generates `docs/module-options.md`; CI fails when the committed copy drifts. (#18)
- `nixosConfigurations.minimal-vm` (#16) and `observability-vm` (#17), bootable with `nixos-rebuild build-vm`.
- `holochain-grafana.adminPasswordFile` (#19) and `secretKeyFile` (#20). Without a `secretKeyFile`, Grafana's secret key is generated once at first boot and never enters the store. (#20)
- New checks built in CI: the NixOS VM tests `vmTest-0_6`, `vmTestWithHapp-0_6` (#16), `vmTestConductorMetrics-0_6`, `vmTestWindtunnel` (#17) and `vmTestGateway` (#18), and `conductorMetricsJq` (#21).
- The example fleet runs Holochain 0.6.3 with hREA happ-0.4.0-beta, Kando v0.17.5 and Requests & Offers v0.5.2, fetched by hash. The hardware stubs of the example and of the `fleet` template carry the HoloPort disk layout (GPT with a `bios_grub` partition and an ESP, GRUB for both firmwares). (#19, #21)
- `CONTRIBUTING.md`, with the VM-test and option-reference rules. (#18)

### Changed

- The VM tests that existed in May are rewritten. `vmTest` boots the 0.7 conductor and checks through the admin CLI that it answers and logs no errors. `vmTestWithHapp` was defined only when a `happs/windtunnel.happ` was present, and no commit ever carried one; it now installs Dino Adventure v0.3.0, fetched by hash, and checks it is installed exactly once, before and after a reboot. (#16) `vmTestGrafana` runs the whole observability path on one node, from the conductor's own stats to the dashboard. (#17)
- The conductor runs with `Type = "notify"` and reads its lair passphrase from a 0600 file in its state directory; its `network` section follows the line (`signal_url` below 0.7, `relay_url` on both). (#16)
- Grafana reads `adminPasswordFile` and `secretKeyFile` as systemd credentials, so the files can be root-owned 0400; both options reject Nix store paths. (#21)
- The boot loader moved out of the placeholder `hardware-configuration.nix` files into `configuration.nix` and `hosts/common.nix`, so replacing a stub with `nixos-generate-config` output keeps it. `#minimal` targets a stock UEFI install with systemd-boot. (#21)
- The fleet template and the example put one `operatorKeys` list on the operator account and on root, so Colmena can log in. (#21)
- The example fleet's lock follows `main` after the stack instead of the May tree. (#23)

### Fixed

- The hApp installer treats a failed `list-apps` while the conductor compiles wasm as "not yet" instead of ending the unit, and no fixed start timeout caps `installerTimeout`. (#16, #21)
- The metrics jq sums `blocked_message_counts` at any depth; it used to write a JSON object into the textfile, which made node_exporter drop every `holochain_*` series. (#21)
- The gateway's `--address` is shell-escaped. (#21)

[Unreleased]: https://github.com/Sensorica/nixos-holochain/commits/main
