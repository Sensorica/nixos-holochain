# Sensorica Lab fleet

The worked example behind the `nixos-holochain` modules: five Holochain edgenodes for the Sensorica Lab workshop, `edgenode-01` doubling as the Grafana monitor node, plus the live ISO participants boot from. It is its own flake so that evaluating the module repository never evaluates Sensorica's machines; copy this directory to start your own fleet.

## Layout

```
examples/sensorica-fleet/
├── flake.nix                      # inputs, the Holochain line, the five nixosConfigurations, the ISO, the colmena hive
├── happs.nix                      # the three hApp bundles, fetched by hash
├── hosts/
│   ├── common.nix                 # shared by every host: user, SSH keys, desktop, edgenode service
│   ├── edgenode-01/
│   │   ├── configuration.nix      # monitor node: adds Grafana/Prometheus
│   │   └── hardware-configuration.nix   # placeholder, replace per machine (below)
│   ├── edgenode-02 … 05/          # peer nodes: hostname + hardware only
│   └── workshop-iso/configuration.nix   # KDE Plasma live ISO with the repo cloned on boot
└── README.md
```

## Holochain line and hApps

The fleet runs **Holochain 0.6.3** (ADR-015), taken from the module repository's own `holochain-0_6` and `hc-0_6` outputs so it cannot drift onto a different 0.6.3 than the one the VM tests ran against. The line is not a preference: each of the three hApps below has a 0.6 release and none has a 0.7 one. The principal re-evaluates this seven days before the workshop date.

Every node installs all three at boot, on one network seed (`sensorica-workshop-2026`), which is what makes the five machines one DHT per app rather than five isolated ones:

| hApp | Version | Bundle |
|---|---|---|
| hREA | `happ-0.4.0-beta` | `hrea.happ` |
| Kando | `v0.17.5` | `kando.happ` |
| Requests & Offers | `v0.5.2` | `requests_and_offers.webhapp`, unpacked at build time |

Requests & Offers publishes a `.webhapp` and nothing else, and a conductor installs a `.happ`, so `happs.nix` unpacks it in a derivation with `hc web-app unpack` from the same line. Nothing binary is committed: every bundle is `pkgs.fetchurl` by sha256 (ADR-012).

Three apps compile their wasm one after another on first boot, which on a Holoport is slow, so `installerTimeout` is 900 s. The installer polls for the result rather than trusting any single admin call, so that is a bound on the whole wait, not on one call.

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

Each host ships a placeholder `hardware-configuration.nix` so the fleet evaluates before any machine exists. It is not a bare stub: it carries the Holoport disk layout of ADR-017, so a machine partitioned the way [`docs/deployment.md`](../../docs/deployment.md) says boots on this file as written.

GPT with a 1 MiB `bios_grub` partition *and* a vfat ESP labelled `boot`, an ext4 root labelled `nixos`, swap labelled `swap`; GRUB installed twice, the UEFI half by NixOS (`device = "nodev"`, `efiSupport`, `efiInstallAsRemovable`, ESP at `/efi-boot`) and the BIOS half by one `grub-install --target=i386-pc` in the runbook. A Holoport boots legacy BIOS only; the laptops the fleet is installed from are usually UEFI; this serves both.

Once a machine exists, generate its real hardware configuration on it and commit that over the placeholder, keeping the `boot.loader` block:

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
