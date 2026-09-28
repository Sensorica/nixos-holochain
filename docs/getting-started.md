# Getting started

The shortest path from a freshly installed NixOS machine to a running Holochain conductor, using the `#minimal` template. It takes one machine, a network connection, and access to its console or an SSH session. No prior Nix flake experience is assumed.

At the end, the machine runs `holochain-conductor.service` at boot, with its admin interface on port 4444 on loopback. If you name a hApp, it is installed on first boot and the app interface is attached on port 8888, also on loopback; a node with no hApp has no app interface.

## 1. Start from NixOS

Install NixOS 26.05 with the official installer. The template boots with systemd-boot, which is what the installer sets up on a UEFI machine; on a legacy-BIOS machine read [`templates/minimal/README.md`](../templates/minimal/README.md) § Firmware assumption before switching.

If the installer fails, the rescue procedure learned on the homelab (taking the install over from a laptop by SSH, reading the installer's log, the IPv6-only DNS failure) is in review in [PR #25](https://github.com/Sensorica/nixos-holochain/pull/25) and lands in [`deployment.md`](deployment.md) once merged.

## 2. Turn on flakes for this shell and get git

A fresh NixOS has flakes disabled and no `git`. Enable flakes for the current shell only, then open a shell with `git` in it:

```bash
export NIX_CONFIG="experimental-features = nix-command flakes"
nix shell nixpkgs#git
```

Step 4 makes flakes permanent on the machine. `sudo nixos-rebuild --flake` does not depend on this setting: it enables flakes for its own run.

## 3. Create the flake

Work in a directory under git, because a flake inside a git repository only sees tracked files:

```bash
mkdir edgenode && cd edgenode && git init
nix flake init -t github:Sensorica/nixos-holochain#minimal
```

Before writing anything, Nix asks four y/N questions about the module repository's binary cache settings (`extra-substituters` and `extra-trusted-public-keys`, and whether to mark each as untrusted). Answer N to all four, or press Enter; the warnings that follow are expected, and step 5 passes the cache explicitly.

This writes `flake.nix`, `configuration.nix`, a placeholder `hardware-configuration.nix` and a `README.md`. The template's `flake.nix` takes the modules from `github:Sensorica/nixos-holochain`, which is `main`. There is no release tag yet; once `v0.1.0` exists, change that input to `github:Sensorica/nixos-holochain/v0.1.0` to pin it (see the [README](../README.md#pinning-a-version)).

Replace the placeholder hardware configuration with this machine's, or the next boot looks for disks by labels this machine may not have:

```bash
sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

## 4. Edit `configuration.nix`

The template's `configuration.nix` becomes the machine's whole system configuration: it replaces `/etc/nixos/configuration.nix`, which stops being read. Carry over anything from that file you still need (networking beyond wired DHCP, locale, keyboard).

**Carry over your own account, or you lose it on the first switch.** The account you created in the installer is declared in `/etc/nixos/configuration.nix`, and NixOS removes a previously declared user that the new configuration no longer declares. The template declares only `operator`, which has no password and no SSH key until you give it one. Copy your `users.users.<your-name>` block from `/etc/nixos/configuration.nix` into this file, keeping `extraGroups = ["wheel"]` so you still have `sudo`, or make sure you can log in as `root` on the console before switching.

Then make three changes:

1. Paste your SSH public key into `users.users.operator.openssh.authorizedKeys.keys`. Without it, the `operator` account has no way in over SSH.
2. Keep flakes on after the switch, and keep the Holochain Foundation's binary cache for later rebuilds, by adding this inside the top-level attribute set:

   ```nix
   nix.settings = {
     experimental-features = ["nix-command" "flakes"];
     substituters = ["https://holochain-ci.cachix.org"];
     trusted-public-keys = ["holochain-ci.cachix.org-1:5IUSkZc0aoRS53rfkvH9Kid40NpyjwCMCzwRTXy+QN8="];
   };
   ```

3. Optionally, name a hApp to install on first boot by uncommenting the `happs` block. `src` is a `.happ` file in this directory (tracked by git) or a `pkgs.fetchurl` of one, and `networkSeed` puts the app on its own network. [`happs/README.md`](../happs/README.md) § Referencing a hApp has a ready fetch-by-hash block for Dino Adventure, a Holochain Foundation demo app built for the 0.7 line this template runs; to use `pkgs.fetchurl`, change the file's first line from `{config, ...}:` to `{config, pkgs, ...}:`.

Change `networking.hostName` too if `edgenode` is not what you want to call the machine.

## 5. Check and switch

```bash
git add flake.nix configuration.nix hardware-configuration.nix README.md
nix flake check --no-build
git add flake.lock
```

The first `nix flake check` resolves the inputs and writes `flake.lock`, which pins the exact revisions of nixpkgs, the modules and Holochain; tracking it is what makes the next rebuild the same system.

The first switch needs the binary cache passed on the command line. The cache in step 4 only reaches `nix.conf` once a switch has activated it, and the `nixConfig` the module repository declares does not reach a flake that imports it. Without the cache, this switch compiles Holochain from source, which takes hours:

```bash
sudo nixos-rebuild switch --flake .#edgenode --option extra-substituters https://holochain-ci.cachix.org --option extra-trusted-public-keys holochain-ci.cachix.org-1:5IUSkZc0aoRS53rfkvH9Kid40NpyjwCMCzwRTXy+QN8=
```

Every later switch is the plain `sudo nixos-rebuild switch --flake .#edgenode`. If a switch leaves the machine in a state you did not want, `sudo nixos-rebuild switch --rollback` returns to the previous generation, and the boot menu lists earlier generations to boot into.

## 6. See it running

The conductor takes a minute or more to report ready on first boot; installing a hApp takes longer, because its wasm is compiled then.

```bash
systemctl status holochain-conductor.service
hc client call --port 4444 list-apps
```

On a node with no hApp configured, `list-apps` prints `[]`. On a node switched to the 0.6.3 line (see the [README](../README.md#supported-holochain-lines)), the same check is `hc sandbox call --running 4444 list-apps`. With a hApp, `systemctl status holochain-happ-installer.service` and `journalctl -u holochain-happ-installer` show the install. [`deployment.md`](deployment.md) § First boot sequence explains what runs in which order, and § Verifying the deployment lists the rest of the checks.

To use `sudo` as `operator` over SSH, give the account a password on the console first: `sudo passwd operator`.

## Where to go next

- **Several machines.** `nix flake init -t github:Sensorica/nixos-holochain#fleet` gives five nodes, Grafana on the first, a Colmena hive and a live ISO; its README walks through deploying it. [`examples/sensorica-fleet/`](../examples/sensorica-fleet/) is the same shape filled in for the Sensorica Lab pilot, with three hApps on the 0.6.3 line. [`deployment.md`](deployment.md) § Fleet (Colmena) has the commands.
- **Observability.** `metricsExporter.enable` and `conductorMetrics.enable` export host metrics and the conductor's own `holochain_*` series; the `holochain-grafana` module draws them on the provisioned "Holochain Fleet" dashboard. To see the dashboard before deploying anything, run the `observability-vm` described in [`deployment.md`](deployment.md) § Seeing the dashboard before deploying a fleet.
- **Rescue.** When the NixOS installer itself fails on the target machine, see the rescue procedure in [PR #25](https://github.com/Sensorica/nixos-holochain/pull/25) (it moves into [`deployment.md`](deployment.md) once merged).
- **Every option.** [`module-options.md`](module-options.md) is the full reference, generated from the module declarations; [`architecture.md`](architecture.md) explains how the pieces fit and how one module serves two Holochain lines.
