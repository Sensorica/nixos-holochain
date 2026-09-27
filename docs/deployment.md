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

The flake declares the Holochain Foundation's binary cache in its `nixConfig`, but Nix only honours that with your consent. If you see

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
| Overview | Fleet status, Services | Per node, one row each: is the node scraped (`up`), is the conductor answering and is that answer fresh (`holochain_conductor_up` read against the metrics age; where a node runs two conductors, the worse of the two), how many hApps are enabled and how many are installed but not, how many systemd units have failed, the fullest disk, memory in use, the hottest sensor, time since boot, and how old the conductor metrics are; then the state of every deployed service on every node, from `node_systemd_unit_state`. Anything that needs looking at turns orange or red |
| Holochain | Conductors up, Conductor peers, Conductor network throughput, Conductor metrics age, Conductor messages, Blocked messages, DHT peers, DHT ops held here vs best peer, DHT seconds since last gossip | What each conductor is doing, from the `holochain_*` series the metrics timer writes, one line per conductor; Conductors up reads a node by its worst conductor; the three DHT panels draw one line or bar per network, named by its `network_label` (see [Names](architecture.md#names)), so five nodes sharing one app still read as one line per DHT, and a node that falls behind pulls its DHT's line down |
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

`holochain_conductor_up{conductor="Holochain"} 0` means the timer is running and the conductor is not answering; check `journalctl -u holochain-conductor`. The `conductor` label is `conductorMetrics.name`. No `holochain_` lines at all means the timer has not fired yet, or `conductorMetrics.enable` is off. A `node_textfile_scrape_error` of 1 with another conductor's textfile in the same directory (a Moss node, say) means the two files declare a family differently: both must be written by `holochain-conductor-exporter`, and node_exporter's log names the family.

Each DHT the conductor is in has its own `holochain_dht_*` series, labelled with the conductor, the installed app id (`app_id`), the role and the DNA hash, and one `holochain_dht_info` line that names it for dashboards (see [Names](architecture.md#names)):

```bash
# one line per cell of every enabled app
curl -s localhost:9100/metrics | grep '^holochain_dht_peers'
# the same DHTs as the conductor reports them
hc sandbox call --running 4444 dump-network-metrics --include-dht-summary   # 0.6 line
hc client call --port 4444 dump-network-metrics --include-dht-summary       # 0.7 line
```

A node alone on its network shows `holochain_dht_peers` 0 and `holochain_dht_seconds_since_gossip` -1 for every DHT. No `holochain_dht_` lines while `holochain_conductor_apps{status="enabled"}` is above zero means `dump-network-metrics` did not answer, or answered in a shape the exporter does not read. The second case is logged in `journalctl -u holochain-conductor-metrics`; the first leaves no trace there, so run the call above by hand. A cell whose DNA the reply does not list gets no series rather than zeros.

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

## Rolling back

```bash
# Roll back to the previous NixOS generation
sudo nixos-rebuild --rollback

# List all generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```
