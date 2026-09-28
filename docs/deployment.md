# Deployment Guide

## Prerequisites

- NixOS on the target machine(s)
- SSH access from the deployer to each node
- Nix flakes enabled (`experimental-features = nix-command flakes` in `nix.conf`)

## Single node

On a machine already running NixOS, start from the `#minimal` template in a directory you keep under git (a flake only sees tracked files):

```bash
mkdir edgenode && cd edgenode && git init
nix flake init -t github:Sensorica/nixos-holochain#minimal

# The placeholder hardware configuration only lets the flake evaluate; replace
# it with this machine's before switching, or the next boot looks for disks by
# labels this machine may not have.
sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix

nano configuration.nix      # SSH key, hostname, hApps
git add flake.nix configuration.nix hardware-configuration.nix README.md
nix flake check --no-build
sudo nixos-rebuild switch --flake .#edgenode
```

The template boots with systemd-boot, as the NixOS installer does on UEFI; `templates/minimal/README.md` says what to change for legacy BIOS.

## Colmena prerequisites

Before running `colmena apply` from `examples/sensorica-fleet`, each host must have:

1. A real `hardware-configuration.nix` replacing the committed placeholder, generated on the target machine:
   ```bash
   sudo nixos-generate-config --show-hardware-config > examples/sensorica-fleet/hosts/edgenode-XX/hardware-configuration.nix
   ```
2. The facilitator's SSH public key in `examples/sensorica-fleet/hosts/common.nix` in the `operatorKeys` list at the top (used for the `sensorica` account and for root, which Colmena connects as; public keys are committed, a flake never sees untracked files).

## Fleet (Colmena)

```bash
cd examples/sensorica-fleet

# Deploy to all nodes in parallel (--impure: Colmena 0.4.0 cannot lock its
# `hive` input in pure mode, see examples/sensorica-fleet/README.md)
colmena apply --impure --on @all

# Deploy to a single node
colmena apply --impure --on edgenode-01

# Dry-run (shows what would change)
colmena apply --impure --dry-run
```

## Workshop ISO

```bash
# Build the ISO
nix build ./examples/sensorica-fleet#nixosConfigurations.workshop-iso.config.system.build.isoImage

# Flash to USB (replace /dev/sdX with your USB device)
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress
sync
```

## Rescuing an install from another machine

When the graphical installer fails on a machine in front of you (a Holoport, a homelab box), take it over from a laptop on the same network instead of debugging at its console. Every step below was run on 2026-09-26, rescuing a homelab install of NixOS 26.05.

### Making the USB stick

Write the ISO directly to the stick and check it byte for byte. Do not boot a NixOS 26.05 ISO through Ventoy: the initrd waits for the ISO's filesystem label (`/dev/disk/by-label/nixos-graphical-26.05-x86_64`), Ventoy never exposes it, and the boot drops to emergency mode. Ventoy's GRUB2 mode (Ctrl+R) did not help either.

```bash
sudo dd if=nixos-graphical-26.05-x86_64-linux.iso of=/dev/sdX bs=4M status=progress conv=fsync
sudo cmp -n "$(stat -c %s nixos-graphical-26.05-x86_64-linux.iso)" nixos-graphical-26.05-x86_64-linux.iso /dev/sdX && echo VERIFIED
```

`dd` returns only once `conv=fsync` has flushed everything, which on a slow stick is minutes after the copy counter reaches 100%. A red `Failed to start Load Kernel Modules` during the live boot is harmless when the boot carries on.

### Letting the laptop in

The stock installer ships an SSH server but does not start it, and its `nixos` user has no password. On the machine, in a terminal of the live session:

```bash
passwd
sudo systemctl start sshd
ip -br -4 a
```

On the laptop, with the address from the last command (it asks for that password once):

```bash
ssh-copy-id -o StrictHostKeyChecking=accept-new nixos@<machine-ip>
```

If nobody can read the address off the screen, find it from the laptop: on a home network, the installer is usually the only host answering on port 22. Replace `192.168.0` with your network's prefix.

```bash
for i in $(seq 1 254); do (timeout 1 bash -c "echo > /dev/tcp/192.168.0.$i/22" 2>/dev/null && echo 192.168.0.$i) & done; wait
```

The workshop ISO (`examples/sensorica-fleet`, `hosts/workshop-iso`) enables `services.openssh` but ships an empty `authorizedKeys` list; putting the facilitator's key there would remove the `passwd` and `ssh-copy-id` steps. Whether its sshd starts at boot has not been checked yet (the upstream installer module keeps sshd out of `multi-user.target`); tracked with the ISO work in #6.

### Reading why the installer failed

The graphical installer (Calamares) logs everything, including `nixos-install`'s output, to a root-only file:

```bash
ssh nixos@<machine-ip> 'sudo grep -a -n -E "error|onInstallationFailed|Starting job" /root/.cache/calamares/session.log | tail -30'
```

`lsblk -f` shows whether the partitions were created. A failed run leaves them mounted under `/tmp/calamares-root-*`, with swap active; the installer then offers only manual partitioning.

### Known failure: downloads fail "after 0 ms"

Symptom: `nixos-install` stops on `unable to download 'https://cache.nixos.org/…narinfo': Could not connect to server … after 0 ms`. Seen on a home router whose DNS answered the installer with an IPv6 address only (`getent ahostsv4 cache.nixos.org` empty) while the machine had no IPv6 route. Check and fix in the live session:

```bash
getent ahostsv4 cache.nixos.org
c="$(nmcli -g GENERAL.CONNECTION device show <iface>)"; sudo nmcli con mod "$c" ipv4.dns "1.1.1.1 9.9.9.9" ipv4.ignore-auto-dns yes && sudo nmcli con up "$c"
nix --extra-experimental-features nix-command store info --store https://cache.nixos.org
```

`<iface>` is the Ethernet interface from `ip -br -4 a` (`enp0s31f6` on the homelab). The connection name is looked up rather than typed because it follows the installer's language: "Wired connection 1" in English, "Connexion filaire 1" in French. On an installed system, a user in the `networkmanager` group can run the two `nmcli` commands without `sudo`. The last line prints `Store URL: https://cache.nixos.org` once the cache is reachable. The installed system asks the same router for DNS, so set `networking.nameservers` in its configuration (or fix the router) before its first `nixos-rebuild`.

### Retrying

Release what the failed run left behind, then relaunch the installer and choose to erase the disk:

```bash
for m in $(findmnt -rn -o TARGET | grep calamares-root | sort -r); do sudo umount "$m"; done
sudo swapoff -a
```

## Trying it without hardware

The root flake ships a single-node configuration so you can run the module on a laptop before touching a Holoport:

```bash
nixos-rebuild build-vm --flake .#minimal-vm
./result/bin/run-*-vm
# at the console (autologin as root):
systemctl is-active holochain-conductor
```

`nixos-rebuild` is absent on non-NixOS hosts (a Linux laptop with plain Nix, or a NixOS container). The same VM is reachable through the flake output it wraps:

```bash
nix build .#nixosConfigurations.minimal-vm.config.system.build.vm
./result/bin/run-*-vm
```

A host that imports the `holochain-edgenode` module gets the Holochain Foundation's binary cache in its `nix.settings` (`services.holochain-edgenode.binaryCache.enable`, on by default), so `holochain` and `hc` download prebuilt. That setting reaches `nix.conf` only once a switch has activated it: the first `nixos-rebuild switch` that brings the module still compiles Holochain from source (the `cargo-src-*` and `holochain-deps` derivations are the sign) unless you pass the cache for that one run:

```bash
sudo nixos-rebuild switch --flake .#<host> --option extra-substituters https://holochain-ci.cachix.org --option extra-trusted-public-keys holochain-ci.cachix.org-1:5IUSkZc0aoRS53rfkvH9Kid40NpyjwCMCzwRTXy+QN8=
```

Every later switch uses the plain command. This root flake also declares the cache in its `nixConfig`, for building its own outputs, but Nix only honours that with your consent. If you see

```
warning: ignoring untrusted flake configuration setting 'extra-substituters'.
Pass '--accept-flake-config' to trust it
```

then the conductor is about to be built from source, which takes hours. Pass `--accept-flake-config`, or add the substituter to your own `nix.conf`:

```
extra-substituters = https://holochain-ci.cachix.org
extra-trusted-public-keys = holochain-ci.cachix.org-1:5IUSkZc0aoRS53rfkvH9Kid40NpyjwCMCzwRTXy+QN8=
```

The first boot is not fast even so: the conductor takes a minute or more to open its admin port on a VM, and installing a hApp is slower still.

## Seeing the dashboard before deploying a fleet

`observability-vm` is the whole observability stack on one machine: an edgenode exporting its conductor's `holochain_*` series, plus Prometheus and Grafana scraping and drawing them. Grafana and Prometheus are forwarded to the host, so a real browser reaches them.

```bash
nixos-rebuild build-vm --flake .#observability-vm
./result/bin/run-observability-vm-vm
# or, on a non-NixOS host:
nix build .#nixosConfigurations.observability-vm.config.system.build.vm
./result/bin/run-observability-vm-vm
```

Then open <http://localhost:13000> (admin / workshop2026) and pick the **Holochain Fleet** dashboard; Prometheus itself is on <http://localhost:19090>. Give it a couple of minutes: the conductor needs a minute or more to come up, the metrics timer fires every 10 seconds in this VM, and the panels need a few points before they draw a line.

The dashboard reads top to bottom, from "is anything wrong" to "why":

| Row | Panels | What it answers |
|---|---|---|
| Overview | Fleet status, Services | Per node, one row each: is the node scraped (`up`), is the conductor answering and is that answer fresh (`holochain_conductor_up` read against the metrics age), how many hApps are enabled and how many are installed but not, how many systemd units have failed, the fullest disk, memory in use, the hottest sensor, time since boot, and how old the conductor metrics are; then the state of every deployed service on every node, from `node_systemd_unit_state`. Anything that needs looking at turns orange or red |
| Holochain | Conductors up, Conductor peers, Conductor network throughput, Conductor metrics age, Conductor messages, Blocked messages | What each conductor is doing, from the `holochain_*` series the metrics timer writes |
| Host health | CPU busy, Memory used, Load average, Disk space used, Disk IO, Temperatures, Host network throughput, Pressure | Whether the machine under the conductor is healthy, from node_exporter, one line per node where the per-device detail is not what you scan for |

Two variables at the top narrow it down. **Instance** picks nodes (All by default, which also takes in nodes that join later). **Units** is the regular expression the Services panel matches unit names against; its default is `services.holochain-grafana.overviewUnits`. Setting that option replaces the default list, so to add a service and keep the rest, write `overviewUnits = lib.mkOptionDefault [ "caddy.service" ];`. The Services panel has a row per node and a column for every listed unit that at least one selected node has: a node that lacks it shows absent in that column, and a unit no selected node has gets no column at all. A node Prometheus cannot reach gets a red cell in a `node unreachable` column. Temperatures, and the Temp column of Fleet status, are empty in this VM and on any machine without hardware sensors; that is expected.

The Conductor column reads more than up or down. **stale** means the metrics timer has not written for over two minutes, so the value it last wrote no longer says anything; **textfile error** means node_exporter rejected a file in its textfile directory and the `holochain_*` series went with it; **unknown** means the node itself is not answering. The two-minute threshold, like the Metrics age colours, assumes `conductorMetrics.interval` at its 30 s default; with an interval above about 90 s every node reads stale, so a fleet that needs a longer interval should provision its own copy of the dashboard (the `dashboards` option) with the 120 s and 300 s thresholds raised.

The dashboard panels are provisioned, not saved by hand. Editing one in the browser will appear to work and will be discarded on the next rebuild; change `modules/dashboards/holochain-fleet.json` instead.

## First boot sequence

1. NixOS boots.
2. `holochain-conductor.service` starts (waits for network). Its `preStart` generates `/var/lib/holochain/lair-passphrase` (mode 0600) if it is not already there, and the conductor reads it over `--piped`. Nothing is prompted and nothing is stored in the Nix store.
3. The unit is `Type = notify`, so it becomes active when the conductor reports readiness rather than when the process starts. On slow or unaccelerated hardware this takes a minute or more; `TimeoutStartSec` is 600s.
4. `holochain-happ-installer.service` installs and enables the configured hApps, then attaches the app WebSocket.
5. The conductor is reachable on `adminPort` (default 4444) and `appPort` (default 8888), both bound to localhost.

Every boot after the first runs the same sequence. The installer is idempotent: it skips `install-app` for apps already present, re-runs `enable-app` unconditionally, and only attaches the app WebSocket if it is not already attached. The passphrase persists in the state directory, so the keystore opens again with nobody present.

## Verifying the deployment

```bash
# Conductor status
systemctl status holochain-conductor

# Follow conductor logs
journalctl -u holochain-conductor -f

# Check hApp installer ran
systemctl status holochain-happ-installer
journalctl -u holochain-happ-installer

# Conductor metrics (metricsExporter.enable + conductorMetrics.enable)
systemctl list-timers holochain-conductor-metrics
curl -s localhost:9100/metrics | grep '^holochain_'
```

`holochain_conductor_up 0` means the timer is running and the conductor is not answering; check `journalctl -u holochain-conductor`. No `holochain_` lines at all means the timer has not fired yet, or `conductorMetrics.enable` is off.

On the monitor node:

```bash
# every configured scrape target should be "health":"up"
curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {scrapeUrl, health, lastError}'

# the provisioned dashboard should be there
# export GRAFANA_ADMIN_PASSWORD first; on a node that kept the module
# default it is the workshop password
curl -s -u "admin:$GRAFANA_ADMIN_PASSWORD" 'localhost:3000/api/search?query=Holochain'

# the Services panel's raw material: one active series per node for the conductor
curl -s --get localhost:9090/api/v1/query \
  --data-urlencode 'query=node_systemd_unit_state{name="holochain-conductor.service",state="active"} == 1' \
  | jq '.data.result[] | .metric.instance'

# any failed unit, on any node, which the Fleet status panel counts
# (mount units included; device, scope and slice units are left out)
curl -s --get localhost:9090/api/v1/query \
  --data-urlencode 'query=node_systemd_unit_state{state="failed"} == 1' \
  | jq '.data.result[] | {instance: .metric.instance, unit: .metric.name}'
```

A node missing from the first answer is either not scraped (check the targets above) or not running its conductor. The second answer is empty on a healthy fleet; each entry is a unit to look at with `systemctl status` on that node.

## Running your own bootstrap and relay

By default every edgenode uses the Holochain Foundation's development bootstrap server and the iroh canary relay, which need the internet and which the Foundation says are not for production hApps. The `holochain-bootstrap` module runs the same service on one of your own machines: `kitsune2-bootstrap-srv`, a single binary that answers peer discovery at `/bootstrap/{space}` and relays iroh traffic at `/relay`, on one TCP port. A fleet on a LAN with no uplink can then still find itself.

On the machine that serves it (a Holoport, say), in its NixOS configuration:

```nix
imports = [nixos-holochain.nixosModules.holochain-bootstrap];
services.holochain-bootstrap = { enable = true; openFirewall = true; };
```

That listens on TCP 443 over plain HTTP and on UDP 7842 for QUIC address discovery. The server keeps nothing on disk: its agent list lives in the unit's private `/tmp` and empties on restart, and conductors re-publish on their own within minutes. Run one server per network; two instances do not share state.

On every edgenode, the three options that point it there (`bootstrap-host` stands for that machine's name or LAN address):

```nix
services.holochain-edgenode = { bootstrapUrl = "http://bootstrap-host:443"; relayUrl = "http://bootstrap-host:443/relay"; relayAllowPlainText = true; };
```

`relayAllowPlainText` is required for an `http://` relay: the conductor refuses one without it, and the module fails evaluation rather than ship a conductor that will not start. All nodes that should see each other must use the same bootstrap server.

Check it from any node:

```bash
curl -sf http://bootstrap-host:443/health
```

```bash
journalctl -u holochain-bootstrap -f
```

To see the other agents a conductor learnt about, on a 0.6 node (`hc client call --port 4444` on 0.7):

```bash
hc sandbox call --running 4444 list-agents
```

Each entry's `url` should start with `http://bootstrap-host.:443/relay/`; iroh writes the host with a trailing dot.

**Two limits, stated plainly.**

- **No TLS means no Moss laptops.** Without `tlsCertFile` and `tlsKeyFile` the server is plain HTTP. Fleet conductors accept that through `relayAllowPlainText`; a packaged Moss 0.15.8 desktop does not, since Moss turns that flag on only in development builds. A laptop joining through this server needs it on HTTPS with a certificate the laptop trusts, which on a LAN without a public domain means your own CA installed on every laptop. The module takes the files (`tlsCertFile`, `tlsKeyFile`, read through systemd credentials, so they stay out of the Nix store) but this repository has not tested a TLS setup.

- **The relay is open.** Anyone who can reach the port can relay traffic through it; the server has no authentication by default. Keep it on the LAN, or behind a firewall, unless that is what you want.

Keep the server on the same Holochain line as the conductors. The module defaults to the 0.6 build (kitsune2 0.4.1, `nixos-holochain.packages.<system>.bootstrap-srv-0_6`); a 0.7 fleet sets `package = nixos-holochain.packages.<system>.bootstrap-srv` (kitsune2 0.5.0).

Cost, measured in the `vmTestBootstrap` VM (one vCPU, 1 GiB, kitsune2 0.4.1 with the module's defaults, so four worker threads and nine threads in all) on 2026-09-27. RSS from `ps`, CPU from the unit's `CPUUsageNSec`:

| Phase | RSS | cgroup memory peak | CPU |
|---|---|---|---|
| Idle, no conductor, 30 s | 5.9 MiB | 7.2 MiB | 0.005 % of one core (2 ms) |
| Two conductors booting until each holds the other's agent info, 36 s | 7.7 MiB | 9.2 MiB | 0.08 % (29 ms) |
| Two conductors connected, 60 s | 7.7 MiB | 9.2 MiB | 0.02 % (10 ms) |

Next to a conductor's gigabyte this is noise, so one Holoport can carry the server beside its own edgenode. Two peers say nothing about a room of fifty; that number is for the lab.

## Rolling back

```bash
# Roll back to the previous NixOS generation
sudo nixos-rebuild --rollback

# List all generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```
