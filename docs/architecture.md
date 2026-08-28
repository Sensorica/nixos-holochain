# Architecture

## Design philosophy

The Holochain ecosystem has two deployment stories today:

1. **Dev environments via Holonix** — Nix-based, well documented, mature.
2. **Production edgenodes via HolOS** — a Buildroot-based appliance image you flash and run, not configure.

`nixos-holochain` fills the gap: a flake-based repo with reusable NixOS modules so that operators can deploy production node fleets with a single `nixos-rebuild`, without flashing a pre-built appliance image.

The architectural bet is simple. HolOS gives you a minimal Buildroot image to flash. This project takes the opposite approach: declarative NixOS configuration you own, so the community can compose Holochain with the rest of their infrastructure rather than around it.

## Module hierarchy

```
flake.nix
└── modules/
    ├── holochain-edgenode.nix     ← core: conductor + lair + hApp installer
    ├── holochain-windtunnel.nix   ← optional: Wind Tunnel scenario runner
    ├── holochain-http-gateway.nix ← optional: HTTP gateway in front of conductor
    ├── pai.nix                    ← optional: PAI per machine
    └── default.nix                ← aggregator
```

Modules are independent. Import only what you need.

## Service dependency graph

```
network-online.target
    └── holochain-conductor.service        (notify: active once the conductor is ready)
            └── holochain-happ-installer.service (oneshot, runs every boot, idempotent)
```

## Deployment model

The root flake ships modules only. A fleet is its own flake that takes this repository as an input; `examples/sensorica-fleet/` is the Sensorica Lab one, with a host per machine and a [Colmena](https://github.com/zhaofengli/colmena) hive:

```
cd examples/sensorica-fleet
colmena apply --impure --on @all
```

Each node is a standard NixOS system. Colmena handles SSH-based parallel deployment. No custom daemon, no extra moving parts.

## State separation

- **Nix store** (`/nix/store`): immutable, shared, garbage collected. All binaries, configs, and scripts.
- **Data dir** (`/var/lib/holochain` by default): mutable, persistent. Conductor state, lair keystore, DHT data.

A `nixos-rebuild switch` never touches the data dir. Rollbacks are safe.

## Two Holochain lines, one module

The module supports Holochain 0.6 and 0.7 from a single option set. Everything that differs is derived from one value, `lib.versionOlder cfg.package.version "0.7"`, and both lines are exercised by real VM tests (`vmTest` / `vmTestWithHapp` on 0.7.0, `vmTest-0_6` / `vmTestWithHapp-0_6` on 0.6.3) rather than asserted. The root flake carries both toolchains: `holonix` pinned to `main-0.7` and `holonix-0_6` pinned to `main-0.6`, with the 0.6 binaries also exposed as `packages.<system>.holochain-0_6` and `hc-0_6`.

Two things differ, and nothing else does.

### 1. The network section

Every key below was read from `holochain --create-config` on each line and from Holo-Host's own 0.6.1 template, then confirmed by booting a conductor on the result.

**0.6 (verified on 0.6.3)** carries three keys:

```yaml
network:
  bootstrap_url: https://dev-test-bootstrap2.holochain.org
  signal_url: wss://dev-test-bootstrap2.holochain.org
  relay_url: https://use1-1.relay.n0.iroh-canary.iroh.link./
```

**0.7 (verified on 0.7.0)** carries two:

```yaml
network:
  bootstrap_url: https://dev-test-bootstrap2.holochain.org/
  relay_url: https://use1-1.relay.n0.iroh-canary.iroh.link./
```

`network.signal_url` was removed from the 0.7 schema; the module keeps `signalUrl` as an option so a 0.6 configuration still expresses it, ignores it from 0.7, and warns when it is set there. `relay_url` is not optional on either line: a 0.6.3 conductor handed a network section of only `bootstrap_url` and `signal_url` refuses to start.

```
The specified config file could not be parsed, because it is not valid YAML. Details:
    network: missing field `relay_url` at line 11 column 3
```

That is why the 0.6 section has three keys rather than the two an earlier draft of this design called for, and it matches Holo-Host/edgenode `docker/conductor-config-0.6.1.template.yaml`, which is where the 0.6 defaults come from. The 0.7 defaults are whatever `holochain --create-config` writes for itself. Neither pair is a production endpoint: `dev-test-bootstrap2` and the iroh canary relay are development infrastructure, and no production bootstrap or relay is documented for either line at the time of writing. Point `bootstrapUrl` and `relayUrl` at your own for a real deployment.

### 2. The admin CLI

From 0.7, admin calls go through `hc client call --port <p>`. On 0.6 that subcommand does not exist: `hc` 0.6.3 offers only `dna`, `app`, `web-app` and `sandbox`, and asking for `hc client call` panics as an unresolvable external subcommand.

```
thread 'main' panicked at crates/hc/src/lib.rs:110:22:
Failed to run external subcommand: Os { code: 2, kind: NotFound, message: "No such file or directory" }
```

The 0.6 equivalent is `hc sandbox call --running <p>`. Below that prefix the two lines are identical — same subcommand names, same arguments, same JSON — so the installer only makes the prefix version-aware.

## The rest of the conductor config

This is what the module writes on the 0.7 line, and what a 0.7.0 conductor accepts:

```yaml
data_root_path: /var/lib/holochain
keystore:
  type: lair_server_in_proc
  lair_root: /var/lib/holochain/ks
admin_interfaces:
  - driver:
      type: websocket
      port: 4444
      allowed_origins: "*"
network:
  bootstrap_url: https://dev-test-bootstrap2.holochain.org/
  relay_url: https://use1-1.relay.n0.iroh-canary.iroh.link./
```

**`allowed_origins` is the string `*`, not `Any`.** `--create-config` prints a Rust `Debug` line containing `allowed_origins: Any` just above the file it writes, and that value serializes to `'*'` in the YAML. A conductor started on a config carrying `allowed_origins: "*"` reaches `Conductor ready.`, so no `--origin` header is needed on the admin call. Pass `--origin` only if you narrow `allowedOrigins` to a specific list.

The full set of top-level keys the 0.7.0 schema accepts is `admin_interfaces`, `data_root_path`, `db_max_readers`, `db_sync_level`, `incoming_request_concurrency_limit`, `keystore`, `network`, `restore_chain_quorum`, `tracing_override`, `tracing_scope`, `tuning_params` and `wasm_backend`.

### `dataDir` has a length limit

The lair keystore listens on a unix socket at `${dataDir}/ks/socket`, and unix socket paths are capped at `SUN_LEN`, 108 bytes. A deep `dataDir` makes the conductor exit during startup with a message that never mentions the config:

```
ERROR holochain::conductor::conductor::builder: Failed to spawn Lair keystore in process
  err={"error":"InvalidInput","message":"path must be shorter than SUN_LEN"}
```

The default `/var/lib/holochain` yields a 28-byte socket path and is safe. If you relocate the data directory, keep it short.

### The lair passphrase and readiness

`lair_server_in_proc` wants a passphrase, and a NixOS service has nobody to type one. This part of the design follows Holo-Host/holo-host `nix/modules/nixos/holochain/default.nix`, which solved the same problem for the 0.5 line.

The conductor unit's `preStart` generates `${dataDir}/lair-passphrase` (mode 0600, 32 random bytes base64-encoded, no trailing newline) the first time it runs and reuses it forever after. `holochain --piped` then reads it from stdin. The file lives in the unit's `StateDirectory` (mode 0700) rather than in the Nix store, so it is neither world-readable nor lost on a rebuild, and the keystore opens again after a reboot with nobody present. `vmTestWithHapp` proves this by cold-booting the VM and re-checking the installed app.

The unit runs as `Type = "notify"`: the conductor signals systemd when it is ready, so `holochain-conductor.service` becomes active when the admin interface is actually usable rather than when the process exists. `TimeoutStartSec` is raised to 600s because an unaccelerated VM needs around 80 seconds to get there. Set `useSystemdNotify = false` to fall back to `Type = "simple"`.

## The hApp installer

These are the exact commands the installer runs, with the flags taken from `<hc> client call <cmd> --help` (0.7.0) and `<hc> sandbox call <cmd> --help` (0.6.3) of the pinned binaries:

```
hc client call --port <adminPort> install-app --app-id <id> <path-to.happ> [network-seed]
hc client call --port <adminPort> enable-app <id>
hc client call --port <adminPort> add-app-ws <appPort> --allowed-origins '*'
hc client call --port <adminPort> list-apps
hc client call --port <adminPort> list-app-ws
```

On the 0.6 line, substitute `hc sandbox call --running <adminPort>` for `hc client call --port <adminPort>`; the rest is unchanged.

`install-app` takes the bundle path and the network seed as positional arguments, in that order; `--app-id` and `--agent-key` are the only options. `add-app-ws` takes the port positionally.

The unit is a oneshot that runs on every boot, so each call has to tolerate already having been made. The three calls behave differently, which is why the script is not a straight list of commands:

| Call | Repeated on an already-installed node | Installer's response |
|---|---|---|
| `install-app` | fails, `AppAlreadyInstalled("<id>")`, exit 1 | guarded by `list-apps` |
| `enable-app` | succeeds, exit 0 | run unconditionally, which is what keeps the app enabled |
| `add-app-ws` | fails, `AddrInUse`, exit 1 | guarded by `list-app-ws` |

Both guards read JSON, and both lines emit the same shapes. `list-apps` returns an array of app records whose identity key is `"installed_app_id":"<id>"` and whose state after enabling is `"status":{"type":"enabled"}`; the bare app id also appears inside the embedded manifest, so anything counting installations has to match the key, not the id. `list-app-ws` returns `[{"port":8888,"allowed_origins":"*","installed_app_id":null}]`.

### A failed call is not a failed install

Installing or enabling a hApp makes the conductor compile the app's wasm. On a small machine that takes longer than the admin client's own request deadline, and the call comes back as an error while the conductor carries on and finishes the work:

```
holochain-happ-installer[1282]: Error: Websocket error: Timeout
holochain-happ-installer[1282]: Caused by:
holochain-happ-installer[1282]:     0: Timeout
holochain-happ-installer[1282]:     1: deadline has elapsed
```

So the installer does not treat a call's exit status as the answer. It runs `install-app` and `enable-app` tolerantly and then polls `list-apps` for the outcome it wanted, failing the unit only if the app never appears or never reaches `enabled` within `installerTimeout`. This is what makes the service survive a first boot on modest hardware; it is also why the VM tests give their node four cores rather than the test driver's default of one.


## Test bundles

The VM tests install real, published hApps, fetched by hash and never committed (ADR-012):

| Test | Line | Bundle | sha256 |
|---|---|---|---|
| `vmTestWithHapp` | 0.7.0 | [Dino Adventure v0.3.0](https://github.com/holochain/dino-adventure/releases/download/v0.3.0/dino-adventure-v0.3.0.happ) | `4dd11f7c5f5ee73f9472827e48ab3538f53f37f819af610bf8de95c10ee74f72` |
| `vmTestWithHapp-0_6` | 0.6.3 | [Kando v0.17.5](https://github.com/holochain-apps/kando/releases/download/v0.17.5/kando.happ) | `a4cdee64fe32720077e0aade94630f24d0da5e91da33ccbe5bfd894d9d359f28` |

## Open questions

See GitHub issues for outstanding implementation decisions:

- Secrets management for network seeds (sops-nix integration?)
- DHT data persistence across config changes
- Conductor version upgrade paths without state loss
- A production bootstrap and relay pair for either line, once the Foundation documents one
