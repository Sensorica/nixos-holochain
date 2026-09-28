# Sensorica Lab fleet

The worked example behind the `nixos-holochain` modules: five Holochain edgenodes for the Sensorica Lab workshop, `sensorica-holoport-01` doubling as the Grafana monitor node, plus the live ISO participants boot from. It is its own flake so that evaluating the module repository never evaluates Sensorica's machines; copy this directory to start your own fleet.

## Layout

```
examples/sensorica-fleet/
├── flake.nix                      # inputs, the five nixosConfigurations, the ISO, the colmena hive, the parity check
├── hosts/
│   ├── common.nix                 # shared by every host: user, SSH keys, desktop, never-sleep, rebuild alias, edgenode service
│   ├── desk.nix                   # the operator desk: launchers, Plasma layout, tools, Avahi, event mode
│   ├── sensorica-holoport-01/
│   │   ├── configuration.nix      # monitor node: adds Grafana/Prometheus and the Moss node
│   │   └── hardware-configuration.nix   # placeholder, replace per machine (below)
│   ├── sensorica-holoport-02 … 05/          # peer nodes: hostname + hardware only
│   └── workshop-iso/configuration.nix   # KDE Plasma live ISO with the repo cloned on boot
└── README.md
```

## Host names

The five machines are `sensorica-holoport-01` to `sensorica-holoport-05`, and each flake output carries its hostname. A NixOS Holoport runs more than a Holochain edgenode (a Moss node, Grafana, a bootstrap server), so the machine is named for what it is and the edgenode stays a role. `sensorica-holoport-01` is the monitor node: Grafana and Prometheus for the whole fleet, and the Sensorica Moss group's always-online node. `02` to `05` are peer nodes, hostname and hardware only.

## Which nixos-holochain the fleet reads

`flake.nix` pins `nixos-holochain` to `github:Sensorica/nixos-holochain/lab/holoport-session`, the branch the Holoports install from, because it carries the modules the fleet uses (the event profile, the Moss node) and `main` does not yet. A fresh clone of that branch needs only the operator key (below) before the install. Point the input back at `github:Sensorica/nixos-holochain` once the lab branch merges.

## Rebuilding a Holoport

Every Holoport has a `rebuild` alias, for root and for `sensorica`:

```bash
rebuild
```

It runs `sudo nixos-rebuild switch --flake /etc/nixos-holochain/examples/sensorica-fleet`, from the checkout the install leaves in `/etc/nixos-holochain` (root and the `wheel` group, so `sensorica` can edit it from the desk); the output matching the hostname is picked without a fragment. It does not pull: that checkout carries the operator key as a local commit, so updating it is a separate `git -C /etc/nixos-holochain pull --rebase`. Only one switch can run at a time; a second one fails with "nixos-rebuild-switch-to-configuration.service was already loaded" and changes nothing.

## A Holoport never sleeps

`hosts/common.nix` disables the `sleep`, `suspend`, `hibernate` and `hybrid-sleep` targets, so no desktop, logind idle action or key can suspend a Holoport. Plasma's power management suspended `sensorica-holoport-01` from its login screen on 2026-09-27 and took its conductors and dashboards with it; `systemctl start suspend.target` now answers that the unit is masked.

## Switches, per Holoport

Each `hosts/sensorica-holoport-0N/configuration.nix` opens with a switches block. Change a value in a text editor (Kate on the desk, `nano` over SSH), save, run `rebuild`. No other file needs to change, and every earlier generation stays in the boot menu, so `sudo nixos-rebuild switch --rollback` undoes a switch that goes wrong.

| Switch | Values | What it does |
| --- | --- | --- |
| `sensorica.desktop` | `"plasma"` (default), `"gnome"`, `"none"` | KDE Plasma with the operator panel, GNOME with the same launchers in the dock, or no graphical session at all (text console and SSH). The node's services run the same either way. |
| `sensorica.eventMode.enable` | `false` (default), `true` | Logs in without a password and opens the room dashboard full screen at boot. Needs a desktop. |
| `services.holochain-edgenode.enable` | `true` (default), `false` | The Holochain conductor and the event's hApps. |
| `sensorica.remoteAccess.enable` | `false` (default), `true` | Joins Sensorica's tailnet through Headscale at `https://hs.sensorica.co` (`hosts/remote-access.nix`), so SSH, Grafana and `rebuild` reach the Holoport from outside the lab. Before switching it on, write a pre-auth key from `headscale preauthkeys create` to `/var/lib/secrets/headscale-authkey` (root only). |

`sensorica-holoport-01` also enables Grafana (`services.holochain-grafana`) and the Moss node (`services.holochain-moss-node`) further down its file; `enable = false` on either turns it off.

## The operator desk

`hosts/desk.nix` is what a person at a Holoport's own screen gets when they log in as `sensorica`. It is self-contained on purpose: copy the file and its two inputs (home-manager `release-26.05` and plasma-manager, both in this flake only; the modules stay desktop-free) to give another NixOS machine the same kind of desk.

- One Grafana entry, on the desktop and in the panel, that opens Grafana's home page on this Holoport: what it runs, with links to the fleet, node, network and Moss pages.
- Launchers pinned to the panel (the dock on GNOME) and in the menu under System: Grafana, Holochain logs (the conductor's journal), Moss node logs (on the host that runs one) and Rebuild, then Konsole and Dolphin.
- On Plasma, a session declared with plasma-manager: that bottom panel on every screen, a CPU and RAM monitor, the tray and the clock; Breeze Dark; no screen lock and no suspend or display-off on AC. The layout is applied at the next login. On GNOME, the same no-lock, no-blank settings through dconf.
- `tmux`, `btop` and the Holochain 0.6 `hc` on PATH, whichever desktop.
- Avahi, so `sensorica-holoport-01.local` resolves on every Holoport and laptop in the lab without a DNS server. The launchers reach Grafana through `sensorica.grafanaUrl`, `http://sensorica-holoport-01.local:3000` by default, and open on its login page.

**Event mode**, off by default and set per host:

```nix
sensorica.eventMode.enable = true;
```

It logs `sensorica` in without a password and opens the room dashboard full screen (Firefox in kiosk mode on the `holochain-now` page) at every boot. On the monitor node it also lets Grafana show dashboards to anonymous viewers with the Viewer role, so the screens need no login; the admin login is unchanged. Turn it on for the day of an event and off again after.

## The Moss node

`sensorica-holoport-01` hosts the Sensorica Moss group's always-online node through `nixos-holochain.nixosModules.holochain-moss-node`, which every host imports and only `01` enables. `docs/moss-node.md` in the module repository describes the service. Two steps per machine, once, both at a terminal as root: write the conductor password to `/var/lib/secrets/moss-node-password`, then ` moss-node join "INVITE_LINK"` with an invite from the Sensorica group in Moss. The Moss page in Grafana is titled "Is the Sensorica group always online?".

## Holochain line and hApps

The fleet runs **Holochain 0.6.3** (ADR-015) and the three workshop hApps below, all from `nixos-holochain.nixosModules.sensorica-event-node` (#33): the module repository's own event profile, layered onto `holochain-edgenode` by every host in `flake.nix`'s `fleetModules`. It is the same export any other host rehearsing the workshop imports, so this fleet and that host cannot drift apart on the package, the hApp set or the seed; `checks.eventProfileParity` in `flake.nix` fails evaluation if `sensorica-holoport-01` ever overrides one of these away from the module's defaults.

The line is not a preference: each of the three hApps below has a 0.6 release and none has a 0.7 one. The maintainers re-evaluate this seven days before the workshop date.

Every node installs all three at boot, on one network seed (`sensorica-workshop-2026`), which is what makes the five machines one DHT per app rather than five isolated ones:

| hApp | Version | Bundle |
|---|---|---|
| hREA | `happ-0.4.0-beta` | `hrea.happ` |
| Kando | `v0.17.5` | `kando.happ` |
| Requests & Offers | `v0.5.2` | `requests_and_offers.webhapp`, unpacked at build time |

Requests & Offers publishes a `.webhapp` and nothing else, and a conductor installs a `.happ`, so `modules/sensorica-happs.nix` (in the module repository) unpacks it in a derivation with `hc web-app unpack` from the same line. Nothing binary is committed: every bundle is `pkgs.fetchurl` by sha256 (ADR-012).

Three apps compile their wasm one after another on first boot, which on a Holoport is slow, so `installerTimeout` is 900 s (also from the profile). The installer polls for the result rather than trusting any single admin call, so that is a bound on each of its waits (per hApp, the install and then the enable settling), not on one call; the unit has no start timeout of its own.

## Consuming the event profile from another host

Any other flake that rehearses the same workshop node (as Soushi's homelab does) builds from the same export instead of repeating it:

```nix
# inputs: holonix-0_6.follows = "nixos-holochain/holonix-0_6";
modules = [nixos-holochain.nixosModules.holochain-edgenode nixos-holochain.nixosModules.sensorica-event-node];
```

That is the whole profile: package, the three hApps, the network seed, the installer timeout and the two metrics options. A host can still override any one of them (a different seed, a trimmed hApp set) with an ordinary assignment; see the comment at the top of `modules/sensorica-event-node.nix` for why that works with `mkDefault`.

## Evaluate

```bash
cd examples/sensorica-fleet
nix flake check --no-build
nix eval .#nixosConfigurations.sensorica-holoport-01.config.system.build.toplevel.drvPath
```

The `nixos-holochain` input points at the `lab/holoport-session` branch for now (see above); a downstream fleet writes `github:Sensorica/nixos-holochain`. From a checkout of this repository, evaluate against the checkout instead so local module changes are what gets tested:

```bash
nix flake check --no-build --override-input nixos-holochain "$(git rev-parse --show-toplevel)"
```

## Hardware configuration

Each host ships a placeholder `hardware-configuration.nix` so the fleet evaluates before any machine exists. It is not a bare stub: it carries the Holoport disk layout of ADR-017, so a machine partitioned that way boots on this file as written. The partitioning and `grub-install` sequence follows holochain/wind-tunnel-runner; `scripts/holoport-install.sh` runs it, and `docs/deployment.md` § "Installing on a Holoport (legacy BIOS)" is the runbook.

GPT with a 1 MiB `bios_grub` partition *and* a vfat ESP labelled `boot`, an ext4 root labelled `nixos`, swap labelled `swap`; GRUB installed twice, the UEFI half by NixOS (`device = "nodev"`, `efiSupport`, `efiInstallAsRemovable`, ESP at `/efi-boot`) and the BIOS half by one `grub-install --target=i386-pc` in the runbook. A Holoport boots legacy BIOS only; the laptops the fleet is installed from are usually UEFI; this serves both.

Once a machine exists, generate its real hardware configuration on it and commit that over the placeholder. Nothing needs keeping: the GRUB block lives in `hosts/common.nix`, because `nixos-generate-config --show-hardware-config` writes filesystems and kernel modules, never a boot loader.

```bash
sudo nixos-generate-config --show-hardware-config > hosts/sensorica-holoport-01/hardware-configuration.nix
```

## Operator SSH keys

Public keys are not secrets, and a flake only ever sees git-tracked files, so the operator keys are committed: paste your `ssh-ed25519 ...` line into the `operatorKeys` list at the top of `hosts/common.nix` before deploying; it goes on the `sensorica` account and on root, which Colmena connects as. A fleet deployed with that list empty has no way in over SSH. Private keys, tokens and passphrases never enter git.

## Deploy

```bash
# one machine
sudo nixos-rebuild switch --flake .#sensorica-holoport-01

# the whole fleet over SSH, in parallel
nix develop            # brings colmena into PATH
colmena apply --impure --on @all
colmena apply --impure --on sensorica-holoport-01
colmena apply --impure --dry-run

# inspect the evaluated hive
colmena eval --impure -E '{nodes, ...}: nodes.sensorica-holoport-01.config.services.holochain-edgenode.enable'
```

`--impure` is required with Colmena 0.4.0 on Nix 2.25: Colmena wraps the flake as an input named `hive`, and pure mode refuses to lock it ("cannot update unlocked flake input 'hive' in pure mode"). Colmena resolves `nixos-holochain` from this directory's `flake.lock`, so `--override-input` does not reach it; bump the lock (`nix flake update nixos-holochain`) to deploy modules newer than the locked revision.

## Workshop ISO

```bash
nix build .#nixosConfigurations.workshop-iso.config.system.build.isoImage
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress
sync
```
