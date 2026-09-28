# Moss always-online node

A Moss group stays reachable when at least one member is online. `wdocker` is Moss's headless node: a Holochain conductor plus a daemon that joins a group, answers Moss's presence pings and installs the group's tagged tools. This page runs it two ways: as a NixOS service (#28), which is how the Sensorica Holoports run it, and by hand on any x86_64 Linux machine with Nix.

## As a NixOS service

`nixosModules.holochain-moss-node` (`modules/holochain-moss-node.nix`) runs wdocker's daemon under systemd, with no terminal and no tmux. It is not part of `nixosModules.default`, because it runs a second conductor beside the edgenode's. The flake's wrapper sets its `package` to `wdocker-0_15` (Moss 0.15.8, Holochain 0.6.1). It needs `services.holochain-edgenode` with its `metricsExporter` enabled, since the Moss readings go through the same exporter and textfile directory; an assertion says so when they are missing.

```nix
services.holochain-moss-node = {
  enable = true;
  name = "sensorica";
  passwordFile = "/var/lib/secrets/moss-node-password";
  group = "Sensorica";
  dashboard.title = "Is the Sensorica group always online?";
};
```

The options:

- `enable`: the node, its readings timer and its unit names on the dashboards. The home page ("What is this machine running?") lists the node as "Moss node" with wdocker's version, and its conductor "Moss" with the Holochain wdocker brings (0.15.8 and 0.6.1 for the flake's `wdocker-0_15`), both read from the package, not from the running node.
- `name`: the wdocker conductor's name, a local label (default `moss-node`).
- `passwordFile`: a root-only file holding the conductor password, with no trailing newline. Only the path reaches the Nix store; systemd passes the file to the daemon as a credential (`LoadCredential`) and the daemon reads it on stdin. When the file is missing the unit fails with `status=243/CREDENTIALS` and retries every 30 s.
- `group`: what the dashboards call the Moss group itself (every `group#` app), from the exporter's second run on.
- `appletNames`: what the dashboards call each tool, keyed by its installed_app_id (`applet#...`, as `moss-node status` prints it). A named tool is also expected, so it reads "Not running" when the conductor stops listing it; a tool left out reads by its kind and a number (Vines 1, Vines 2).
- `partNames`: what the dashboards call each part (DNA role) of each kind of Moss app, keyed by kind. The defaults name the group's `group`, `foyer` and `assets` roles and Vines' `rVines` and `rFiles`.
- `dashboard.enable`: provision the Moss page in this machine's Grafana. It defaults to `config.services.grafana.enable`, so the monitor node gets the page even when it runs no Moss node; the page lists every Moss node its Prometheus scrapes.
- `dashboard.title`: the page's title. The page's uid is `sensorica-moss-node`; it is tagged `moss`, which is how the home page finds it to link to it.

What it runs:

- The service `moss-node.service` runs `wdaemon NAME` as the system user `moss-node`, with `HOME=/var/lib/moss-node` (the state directory, mode 0700). The daemon creates the conductor on its first start; wdocker keeps it under `/var/lib/moss-node/.local/share/wdocker/0.15.x/`. The unit restarts on failure after 30 s.
- The helper `moss-node`, run as root: `moss-node join "INVITE_LINK"` runs `wdocker join-group` as the node's user (it asks for the conductor password, a profile name and a description) and then restarts the service, because the daemon pings Moss only for the groups present when it starts. Start the line with a space so the link stays out of shell history. `moss-node status` prints the unit's state, the conductor, its groups and its apps; `moss-node logs` follows the journal; `moss-node restart` restarts the daemon; `moss-node wdocker ARGS...` runs any wdocker command as the node's user.
- The timer `moss-node-metrics.timer` runs nixos-holochain's own conductor exporter every 30 s under the conductor name `Moss`, into `moss-node.prom` in the edgenode's textfile directory, beside the edgenode's own file (one program, one set of HELP texts, #47). wdocker picks a random admin port and allowed origin at every start and writes both into its conductor config, so the exporter reads them from there on every run. The unit reads as "Moss node" and the timer as "Moss readings (timer)" on the node page.

Joining is the one step that stays at a terminal, because the invite link carries the group's network seed, which must never reach a file. Per machine, once: write the password file, then join.

```bash
printf '%s' "$(systemd-ask-password 'Moss conductor password:')" | install -m 0400 /dev/stdin /var/lib/secrets/moss-node-password
```

```bash
 moss-node join "INVITE_LINK"
```

`INVITE_LINK` is an invite from the group in Moss (group settings), in double quotes.

The checks: `checks.x86_64-linux.vmTestMossNode` starts the service in a VM with no terminal, waits for "Daemon ready.", checks the user, the helper, the `holochain_conductor_up{conductor="Moss"} 1` reading and a restart, and boots a second machine without the password file that must never reach "Daemon ready."; `checks.x86_64-linux.moss-dashboard` and `checks.x86_64-linux.moss-names` check the page and the names program, each also run on broken copies of its input that it must reject.

## By hand

The rest of this page runs the packaged `wdocker` by hand, which is what the service automates. It is still the way to try a group on a machine that is not NixOS.

### What the package is

`packages.x86_64-linux.wdocker-0_15` builds wdocker from the Moss monorepo at tag `v0.15.8` (the release whose desktop app bundles Holochain 0.6.1), not from npm: `@theweave/wdocker@0.15.4` on npm cannot start, because its manifest still points at `file:` workspaces that are not published.

It ships the Holochain 0.6.1 binary wdocker expects, fetched from the Holochain release and pinned to the sha256 Moss itself pins in `holochain-checksums.json`. The binary is patched for the Nix store, so NixOS needs no `nix-ld`, and wdocker never downloads a binary at runtime: the wrapper sets `WDOCKER_HOLOCHAIN_BINARY` to it. Setting that variable yourself points wdocker at another binary.

`wdocker --version` prints `0.15.4`, the version in wdocker's own `package.json` at that tag.

### Running it

Every command except the daemon prompts on a TTY (`@inquirer/prompts`), so run the node inside `tmux` or `screen`:

```bash
nix shell github:Sensorica/nixos-holochain#wdocker-0_15
```

```bash
wdocker run NAME
```

`run` creates the conductor, asks for a new password and stays attached, printing the daemon's log. `NAME` is any local label. In a second pane, join the group with an invite link from Moss, in double quotes; it asks for the conductor password, a profile name and a description for the node:

```bash
wdocker join-group NAME "INVITE_LINK"
```

The invite link carries the group's network seed (the part before `&progenitor=`). Do not commit it, paste it into an issue, or leave it in shell history (a leading space keeps it out when `HISTCONTROL=ignorespace`).

**Then restart the node.** The daemon sets up the ping and pong that make Moss show the node online only for groups that are present when it starts (`wdocker/src/daemon/daemon.ts`, lines 124 to 189 at `v0.15.8`). A group joined afterwards is hosted, but shows offline in Moss until the next start. Stop the attached `wdocker run` or `wdocker start` with Ctrl-C, then:

```bash
wdocker start NAME
```

Check the state with `wdocker list`, `wdocker list-groups NAME` and `wdocker list-apps NAME`. The group's DNA hash in `list-groups` is the group's id.

### Tools are joined only when tagged

The daemon checks the group every five minutes and installs only the tools a steward has marked for always-online nodes: in Moss, group settings, Group Tools, the tool's card, "always-online nodes should install this tool". In the code, it keeps the applets whose metadata carries the `always-online` tag (`daemon.ts` lines 294 to 295, the tag defined in `shared/group-client/src/types.ts` line 163). An untagged tool is never installed on the node.

A tagged tool can still fail with `sha256 of the fetched webhapp does not match` when the webhapp at the tool list's URL is not the build the group recorded. wdocker skips the download when `happs/<sha256>.happ` already holds the right bytes, and a Moss desktop keeps its installed tools the same way (`data/happs/<sha256>.happ`), so copying a member's stored hApp into the node's `happs` directory is the workaround found on 2026-09-27 (#28).

### Where things live

- Data: `~/.local/share/wdocker/0.15.x/` (the `0.15.x` part follows wdocker's breaking version). Each conductor sits under `conductors/NAME/`, hApps under `happs/`.

- The admin port and its allowed origin are random at each start, and written into `conductors/NAME/conductor/conductor-config.yaml`.

- The conductor keeps its keystore in process (lair in process) and unlocks it with the password the daemon reads on stdin.

- Network: bootstrap and signal at `https://bootstrap.moss.social` and `wss://bootstrap.moss.social`, relay at `https://iroh-relay.moss.social./` (`wdocker/src/const.ts` lines 12 to 28).

### What stays interactive

The one entry point that needs no TTY is the daemon itself: `wdaemon NAME` reads the conductor password on stdin, which is how the package's VM check (`checks.x86_64-linux.vmTestWdocker`) starts a conductor. Joining a group still needs `wdocker join-group` at a terminal. Moss added environment variables for a headless start later (lightningrodlabs/moss PR #224); they are not on tag `v0.15.8` and this package does not carry them. The service above drives the daemon over stdin, with the password as a systemd credential, and needs neither.
