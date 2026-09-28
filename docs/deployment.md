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
colmena apply --impure --on sensorica-holoport-01

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

## Installing on a Holoport (legacy BIOS)

A Holoport boots legacy BIOS only, so the NixOS graphical installer's default UEFI layout does not boot on it. One script, [`scripts/holoport-install.sh`](https://github.com/Sensorica/nixos-holochain/blob/main/scripts/holoport-install.sh), does the whole sequence of ADR-017: GPT with a 1 MiB `bios_grub` partition, a vfat ESP labelled `boot`, an ext4 root labelled `nixos` and 8 GiB of swap labelled `swap` at the end; root mounted at `/mnt` and the ESP at `/mnt/efi-boot`; `nixos-install`; then `grub-install --target=i386-pc` for the BIOS half. The same disk also boots on UEFI, because NixOS writes the EFI half from `hosts/common.nix`. The flake publishes the script as `packages.x86_64-linux.holoport-install` with every tool it calls pinned, and `checks.x86_64-linux.vmTestHoloportInstall` runs that package under SeaBIOS.

The script erases exactly the disk you name and nothing else. It refuses to run without one, shows that disk and the disks it will leave alone, and waits for you to type the disk's name back. It also refuses when another disk already carries one of its three labels, because the installed system mounts by label.

### The machines

| | HoloPort | HoloPort+ |
|---|---|---|
| CPU, RAM | dual-core Pentium 3.5 GHz, 8 GB | quad-core i7, 16 GB |
| Disks | 1 TB HDD at `/dev/sda` | 128 GB SSD at `/dev/sda`, 2 TB HDD at `/dev/sdb` |
| Install on | `/dev/sda` | `/dev/sda` (the SSD); `/dev/sdb` stays as it is |

Both have Ethernet and no Wi-Fi, HDMI and a USB keyboard, no DMI data, and legacy BIOS. On the base HoloPort, tapping Esc at power-on opens the firmware boot menu; pick the stick there, because the GRUB menu on the internal disk belongs to HoloOS and never lists it. The key for the BIOS setup, and the HoloPort+'s keys, are not known yet: try Del or F2 for setup, and F7, F8, F11 or F12 for the boot menu.

### 1. Boot an installer and get network

Write the workshop ISO (above) or the stock NixOS 26.05 minimal ISO to a USB stick with `dd`, plug the Holoport into the lab router with Ethernet, and boot the stick from the boot menu. Use a USB 2 port: from a USB 3 port the base HoloPort's live system fails with `SQUASHFS error: Unable to read page` and freezes. Prefer a text console to a graphical ISO, whose desktop freezes on the base HoloPort's Intel HD 610; if you booted one and it froze, Ctrl+Alt+F1 then Ctrl+Alt+F3 reaches a console logged in as `nixos`, and `sudo systemctl stop display-manager` stops the frozen session. Then, in a root shell (`sudo -i` on either ISO):

```bash
ip -br -4 a
nix --extra-experimental-features nix-command store info --store https://cache.nixos.org
lsblk -d -o NAME,SIZE,ROTA,MODEL
```

The first line shows the address the router gave the box; the second prints `Store URL: https://cache.nixos.org` once the binary cache is reachable; the third confirms which disk is which before anything is erased.

### 2a. Install from the Holoport itself

Nearly everything is downloaded rather than built: packages come from cache.nixos.org and from the Holochain cache, which the script passes to `nixos-install` since the target has no `nix.conf` yet; only small derivations such as the unpacked Requests & Offers bundle and the configuration files are built on the box. Clone the repository, put your SSH public key in the `operatorKeys` list at the top of `examples/sensorica-fleet/hosts/common.nix`, then run the script against your checkout:

```bash
git clone https://github.com/Sensorica/nixos-holochain /root/nixos-holochain
cd /root/nixos-holochain
nano examples/sensorica-fleet/hosts/common.nix
nix --extra-experimental-features 'nix-command flakes' run --accept-flake-config .#holoport-install -- /dev/sda ./examples/sensorica-fleet#sensorica-holoport-01
```

Type `/dev/sda` when it asks. It asks once more at the end, for a root password for the console, but only when it runs in a terminal: `nixos-install` skips that prompt when its input is not one (a background or piped SSH session), and then `passwd`, run in the shell `nixos-enter --root /mnt` opens, sets it before the reboot. On the base HoloPort, with its slow disk and two cores, expect this to take a while; path 2b moves the work to a laptop.

Before the first boot, keep the checkout (with your key) on the installed disk. The Sensorica fleet rebuilds from `/etc/nixos-holochain`, owned by root and the `wheel` group so the `sensorica` operator can edit it:

```bash
install -d -m 2775 -g wheel /mnt/etc/nixos-holochain && cp -a /root/nixos-holochain/. /mnt/etc/nixos-holochain/ && chgrp -R wheel /mnt/etc/nixos-holochain && chmod -R g+rwX /mnt/etc/nixos-holochain && git -C /mnt/etc/nixos-holochain config core.sharedRepository group
```

### 2b. Install from a laptop

The laptop builds the system and copies it straight onto the Holoport's new root partition over SSH, so the Holoport only partitions, receives and writes the boot loader. The laptop needs the Holochain cache in its own `nix.conf` (see [Trying it without hardware](#trying-it-without-hardware)), or it compiles the conductor.

On the laptop, from a checkout with your key already in `operatorKeys`:

```bash
nix build ./examples/sensorica-fleet#nixosConfigurations.sensorica-holoport-01.config.system.build.toplevel --out-link sensorica-holoport-01-system
```

On the Holoport, give root a password for the installer session and start its SSH server (the installer ships one but does not start it):

```bash
passwd
systemctl start sshd
```

Back on the laptop, with `HOLOPORT_IP` being the address from step 1, send your key, then start the install over SSH:

```bash
ssh-copy-id root@HOLOPORT_IP
ssh -t root@HOLOPORT_IP "nix --extra-experimental-features 'nix-command flakes' run --accept-flake-config github:Sensorica/nixos-holochain#holoport-install -- /dev/sda $(readlink -f sensorica-holoport-01-system)"
```

The script partitions the disk, sees that the system is not on the Holoport yet, prints the exact `nix copy` command and waits. Run it in a second terminal on the laptop; it has this shape:

```bash
nix copy --to "ssh://root@HOLOPORT_IP?remote-store=/mnt" "$(readlink -f sensorica-holoport-01-system)"
```

`remote-store=/mnt` writes into the new root partition rather than the installer's own store, which lives in RAM and is too small for the event node's closure (about 10 GiB, most of it the desktop). The script carries on by itself once the copy lands.

### 3. Before the first boot

`/mnt` is still mounted when the script ends. sensorica-holoport-01 runs Grafana with its admin password read from a file, which has to exist before Grafana first starts; `NEW_PASSWORD` is the one you choose. It also runs the [Moss node](moss-node.md), whose conductor password is read from a file too: without it `moss-node.service` fails with `status=243/CREDENTIALS`, retries every 30 s, and the machine reads "A service is down". The `systemd-ask-password` line asks for a new Moss conductor password and writes it with no trailing newline:

```bash
install -d -m 0700 /mnt/var/lib/secrets
install -m 0400 /dev/null /mnt/var/lib/secrets/grafana-admin-password
printf '%s' 'NEW_PASSWORD' > /mnt/var/lib/secrets/grafana-admin-password
printf '%s' "$(systemd-ask-password 'Moss conductor password:')" | install -m 0400 /dev/stdin /mnt/var/lib/secrets/moss-node-password
umount -R /mnt && swapoff -a && reboot
```

Remove the USB stick while the Holoport restarts. It boots from its disk through the BIOS GRUB.

### 4. Verify

On the Holoport, or over SSH as `sensorica` or root with the key from `operatorKeys`:

```bash
systemctl is-active holochain-conductor moss-node
systemctl status holochain-happ-installer
journalctl -u holochain-happ-installer --no-pager | grep 'Enabled app'
curl -s -u "admin:NEW_PASSWORD" 'localhost:3000/api/search?query=Holochain'
```

The first boot compiles three hApps, so `holochain-happ-installer` can take several minutes to finish on a Holoport (about a minute in the VM check). The conductor and the Moss node should each answer `active`; the journal should end with `hc-sandbox: Enabled app: "hrea"`, `"kando"` and `"requests-and-offers"`; and the last line should return the **Holochain Fleet** dashboard, which is also at `http://HOLOPORT_IP:3000` from a laptop on the same network. [Verifying the deployment](#verifying-the-deployment) has the metrics checks.

The Moss node hosts no group until it joins one. Once per machine, as root on the Holoport, run `moss-node join "INVITE_LINK"` with an invite from the Sensorica group in Moss, starting the line with a space so the link stays out of shell history, as described in [Moss always-online node](moss-node.md#as-a-nixos-service); `moss-node status` then lists the group.

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

## Seeing the dashboards before deploying a fleet

`observability-vm` is the whole observability stack on one machine: an edgenode exporting its conductor's `holochain_*` series, plus Prometheus and Grafana scraping and drawing them. Grafana and Prometheus are forwarded to the host, so a real browser reaches them.

```bash
nixos-rebuild build-vm --flake .#observability-vm
./result/bin/run-observability-vm-vm
# or, on a non-NixOS host:
nix build .#nixosConfigurations.observability-vm.config.system.build.vm
./result/bin/run-observability-vm-vm
```

Then open <http://localhost:13000> (admin / workshop2026). Grafana's home page is **What is this machine running?**, opened on the machine Grafana runs on; Prometheus itself is on <http://localhost:19090>. Give it a couple of minutes: the conductor needs a minute or more to come up, the metrics timer fires every 10 seconds in this VM, and the panels need a few points before they draw a line.

Five dashboards ship, all tagged `holochain`, each titled with the one question its reader asks, and each linking to the others:

| Dashboard (uid) | Reader | What it answers |
|---|---|---|
| What is this machine running? (`holochain-home`) | Anyone opening Grafana: it is the home page, on the machine Grafana runs on, with a node picker for any other | The machine in words (state, host name, NixOS release, kernel, uptime, processor, memory and fullest disk); every service it runs, worst first, with its state, the version of what it runs and when it last started; each Holochain conductor with the service that runs it, its Holochain version and whether it answers; each app on them in the six words; and links to the other pages and, where there is one, the Moss page |
| Is the Holochain network working? (`holochain-now`) | The room, on a shared screen (add `?kiosk` to the URL) | Are the readings current, which machines are on, is each app working on each machine and connected to how many others, did the latest write in the room's app reach every machine, and how long since each app last heard from anyone |
| Which Holochain node needs attention? (`holochain-fleet`) | Whoever runs the fleet | How many machines are unreachable, conductors silent or stale, app parts cut off or behind, machine problems; one row per machine, worst first; the problems in words; the watched services that are down; the app matrix; each machine's status over time; and a collapsed Machines row |
| Is this node working, app by app? (`holochain-node`) | An operator with one machine, or anyone following a link from the fleet page | Each conductor on the machine, its apps, and one row per app part: its state, other computers, the share of its best peer's data it holds, when it last heard from anyone, what it is still fetching; every service the machine runs, by name, with its state; then the machine itself in collapsed rows |
| Is this app in step on every node? (`holochain-network`) | The facilitator asked "did my message reach the others?", or the operator after a Lost contact | One app network across every machine: how many run it, whether any is cut off or behind, a step chart of the data each holds, and each machine's status over time |

Every app part reads one of six words, worst first: **Not running**, **No fresh readings**, **Lost contact**, **No one else yet** (grey, and normal for a machine alone), **Catching up** and **In step**. The room and fleet pages explain each in a sentence at the bottom. They are computed once, by the recording rules of `modules/holochain-rules.nix`, so no two pages can disagree; a machine reads by its worst conductor, and an app by its worst part. No page shows a hash, an installed app id or a scrape address, except the collapsed "For bug reports" row of the network page, which exists to be pasted into an issue.

Each machine lists the services it runs, from the modules enabled on it: the conductor, the app installer, the readings timer, the HTTP gateway, the local bootstrap and relay, the Wind Tunnel runner, Prometheus and Grafana on the monitor, and beside them node_exporter, sshd, Tailscale and the Nix daemon when they are enabled. The home page lists them by name with their state, the version of the package each runs (from Nix, a dash where a unit declares none) and when each last started; the node page lists them by name with their state; the fleet page lists the ones that are not running; a machine's tile on the room screen reads "A service is down" while one has failed, keeps failing and restarting, has stopped or does not answer. The table of every service and where its name and state come from is in [architecture.md](architecture.md#services-from-what-each-node-runs). A machine needs node_exporter's textfile collector for its list to reach the pages; an edgenode and a monitor have it already.

Two options feed the pages. `overviewUnits`, on the monitor, adds units to watch on every machine that runs them, with the name a person reads for each: `overviewUnits = { "caddy.service" = "Web server"; };` (a list, `[ "caddy.service" ]`, still works and shows the unit name). A service of your own on one machine goes in that machine's own list instead: `services.holochain-services.units."caddy.service" = "Web server";`. `room` (`app`, `part`, `label`) picks the one app part whose writes the room screen follows; left unset, that chart says so. Temperatures are empty in this VM and on any machine without hardware sensors; that is expected.

The thresholds behind the words (readings older than 90 s, 10 minutes without contact, 95% of the best peer's data) are `services.holochain-grafana.states`. The provisioned dashboards follow them: every colour step that stands for a state threshold, and every sentence that quotes one, is rewritten from the option on its way into the store. A dashboards directory outside the store is not rewritten, so it keeps the defaults.

The dashboards are provisioned, not saved by hand. Editing one in the browser will appear to work and will be discarded on the next rebuild; change the JSON in `modules/dashboards/` instead, and run `checks.dashboardLabels` and `checks.dashboardQueries`.

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

# the four provisioned dashboards should be there
# export GRAFANA_ADMIN_PASSWORD first; on a node that kept the module
# default it is the workshop password
curl -s -u "admin:$GRAFANA_ADMIN_PASSWORD" 'localhost:3000/api/search?tag=holochain' | jq -r '.[].uid'

# every node by name, with its state (4 is Running, 2 A service is down)
curl -s --get localhost:9090/api/v1/query \
  --data-urlencode 'query=holochain:node_state' \
  | jq '.data.result[] | {node: .metric.node, state: .value[1]}'

# what the problem lists say, one sentence per problem
# (failed units, mount units included, full disks, silent conductors)
curl -s --get localhost:9090/api/v1/query \
  --data-urlencode 'query=holochain:node_problem' \
  | jq '.data.result[] | {node: .metric.node, problem: .metric.problem}'
```

A node missing from the second answer is not scraped (check the targets above). The third answer is empty on a healthy fleet; each entry names what to look at, a failed unit with `systemctl status` on that node.

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

On the dashboards the server is "Local bootstrap and relay", among the services of the machine that runs it. A timer asks its `/health` every 30 seconds, so a server that runs and does not answer reads Not answering, not Running, and turns that machine's tile on the room screen to A service is down. This needs node_exporter's textfile collector on that machine: an edgenode or a monitor has one; on a machine that runs only the server, point `services.holochain-services.textfileDirectory` at the directory its node_exporter reads.

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
