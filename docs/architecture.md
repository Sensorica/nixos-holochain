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
├── modules/
│   ├── holochain-edgenode.nix     ← core: conductor + lair + hApp installer + metrics
│   ├── conductor-metrics.jq       ← dump-network-stats → Prometheus text
│   ├── holochain-grafana.nix      ← optional: Prometheus + Grafana for a fleet
│   ├── dashboards/                ← provisioned Grafana dashboards
│   ├── holochain-windtunnel.nix   ← optional: donate the machine to the Foundation's Nomad cluster
│   ├── holochain-http-gateway.nix ← optional: HTTP gateway in front of the conductor
│   └── default.nix                ← aggregator
├── packages/
│   └── holochain-http-gateway.nix ← the hc-http-gw build, one release per Holochain line
└── templates/
    ├── minimal/                   ← nix flake init -t …#minimal: one edgenode
    └── fleet/                     ← nix flake init -t …#fleet: five nodes, Grafana, ISO
```

Modules are independent. Import only what you need.

### Units each module creates

| Unit | Type | Condition |
|------|------|-----------|
| `holochain-conductor.service` | notify (simple when `useSystemdNotify = false`) | `holochain-edgenode.enable` |
| `holochain-happ-installer.service` | oneshot, `RemainAfterExit`, runs every boot | `happs != {}` |
| `prometheus-node_exporter.service` | simple | `metricsExporter.enable`, or `holochain-grafana.enable` |
| `holochain-conductor-metrics.service` | oneshot, driven by the timer | `conductorMetrics.enable` |
| `holochain-conductor-metrics.timer` | `OnBootSec` / `OnUnitActiveSec` = `interval` | `conductorMetrics.enable` |
| `grafana.service` | simple | `holochain-grafana.enable` |
| `prometheus.service` | simple | `holochain-grafana.enable` |
| `holochain-http-gateway.service` | simple, `DynamicUser`, restarts until the conductor answers | `holochain-http-gateway.enable` |
| `podman-wind-tunnel-runner.service` | simple, from `virtualisation.oci-containers` | `holochain-windtunnel.enable` |

## Service dependency graph

```
network-online.target
    └── holochain-conductor.service        (notify: active once the conductor is ready)
            ├── holochain-happ-installer.service (oneshot, runs every boot, idempotent)
            └── holochain-conductor-metrics.timer
                    └── holochain-conductor-metrics.service (oneshot, every 30s)
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

Switching a node to the 0.6 line is two options:

```nix
services.holochain-edgenode = {
  enable = true;
  package = inputs.holonix-0_6.packages.${pkgs.system}.holochain;
  hcPackage = inputs.holonix-0_6.packages.${pkgs.system}.hc;
};
```

or, against this flake's own outputs, `nixos-holochain.packages.${system}.holochain-0_6` and `hc-0_6`. Everything else follows: the network section, the admin CLI prefix, and the HTTP gateway release.

Three things differ, and nothing else does.

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

The 0.6 equivalent is `hc sandbox call --running <p>`. Below that prefix the two lines are identical: same subcommand names, same arguments, same JSON, so the installer only makes the prefix version-aware.

### 3. The HTTP gateway release

The gateway is a separate program with its own release train, and it links the conductor's client libraries, so a build cannot straddle the two lines. Upstream publishes one gateway line per Holochain line, which `modules/holochain-http-gateway.nix` selects from the same `cfg.package.version` the network section is derived from. See "The HTTP gateway" below.

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


## Observability

The workshop's high point is a dashboard showing the fleet's Holochain traffic. Three pieces make it, and only the first is Holochain-specific.

### 1. Conductor metrics

There is no Prometheus endpoint on a Holochain conductor. There is an admin call, `dump-network-stats`, that answers with the Kitsune2 transport's own numbers, and node_exporter has a textfile collector that serves any `*.prom` file in a directory. So the module bridges the two with a timer rather than with a daemon: a long-lived exporter holding an admin websocket open would be one more thing to supervise, restart and version, for exactly the same series.

`holochain-conductor-metrics.timer` fires every `conductorMetrics.interval` (default 30s). Its oneshot service runs

```
hc client call --port 4444 dump-network-stats        # 0.7
hc sandbox call --running 4444 dump-network-stats     # 0.6
```

pipes the reply through `modules/conductor-metrics.jq`, and moves the result into `metricsExporter.textfileDirectory` atomically, because the collector may read the directory at any moment.

The reply is Kitsune2's `TransportStats` (`kitsune2` `crates/api/src/transport.rs`), wrapped by Holochain with `blocked_message_counts`. It is byte-identical on both lines. Verified against the pinned binaries, on a bare conductor with no app installed and no peers:

```
$ hc client call --port 4471 dump-network-stats            # holochain 0.7.0
{"transport_stats":{"backend":"iroh","peer_urls":["https://use1-1.relay.n0.iroh-canary.iroh.link.:443/57b3f7ba59f9e69714ce3033240108fbffba2f31d1d584df540eb4f8a788a164"],"connections":[]},"blocked_message_counts":{}}

$ hc sandbox call --running 4461 dump-network-stats        # holochain 0.6.3
{"transport_stats":{"backend":"iroh","peer_urls":["https://use1-1.relay.n0.iroh-canary.iroh.link.:443/eee66b1f1962c1132a11638571f477e9c90575f4378c636c81096502db1c9d9c"],"connections":[]},"blocked_message_counts":{}}
```

`dump-network-metrics`, the other candidate the issue named, answers `{}` on a conductor with no app installed, because it reports per-DNA gossip state and there is none. `dump-network-stats` always has something to say, which is why the gauges are derived from it.

Each entry of `connections` carries `pub_key`, `send_message_count`, `send_bytes`, `recv_message_count`, `recv_bytes`, `opened_at_s` and `is_direct`. These are the series derived from them:

| Series | Type | Meaning |
|---|---|---|
| `holochain_conductor_up` | gauge | 1 when the admin interface answered, 0 when it did not |
| `holochain_conductor_peer_connections` | gauge | Transport connections currently held |
| `holochain_conductor_direct_peer_connections` | gauge | Of those, the ones that upgraded off the relay |
| `holochain_conductor_peer_urls` | gauge | Peer URLs this conductor can be reached at |
| `holochain_conductor_network_sent_bytes_total` | counter | Bytes sent, summed over current connections |
| `holochain_conductor_network_received_bytes_total` | counter | Bytes received, summed over current connections |
| `holochain_conductor_network_sent_messages_total` | counter | Messages sent, summed over current connections |
| `holochain_conductor_network_received_messages_total` | counter | Messages received, summed over current connections |
| `holochain_conductor_blocked_messages_total` | counter | Messages refused, summed over every block reason |
| `holochain_conductor_metrics_scrape_timestamp_seconds` | gauge | When the textfile was last written |

Two properties are worth stating explicitly:

- **A down conductor reports `holochain_conductor_up 0`, it does not disappear.** The script writes the file whether or not the call succeeded, so a dead node is visible on the dashboard rather than absent from it. This is the difference between a panel that says "one node is down" and a panel that quietly draws four lines instead of five.
- **The byte and message counters describe live connections only.** They sum over the connections the conductor holds at that instant, so a peer that disconnects takes its totals with it and the counter can go down. `rate()` over them is throughput of current links, which is what the dashboard draws; they are not lifetime totals and should not be read as such.

### 2. Prometheus and Grafana

`holochain-grafana` runs both on the monitor node and provisions the pair that makes a dashboard work without a human: a Prometheus data source with the fixed uid `holochain-prometheus`, and every JSON file under `modules/dashboards/`. The shipped dashboard, "Holochain Fleet", draws CPU, memory and host network from node_exporter next to the conductor series, so a spike in one is legible against the other.

`vmTestGrafana` runs the whole path in one VM: it waits for the conductor, asserts `holochain_conductor_up 1` appears on `/metrics`, asserts every Prometheus target reports `"health":"up"`, asserts Prometheus kept the series, and asserts Grafana's search API returns the provisioned dashboard and its data source.

A fleet is the monitor node naming its peers and every node exporting:

```nix
# the monitor node
services.holochain-grafana = {
  enable = true;
  openFirewall = true;
  scrapeTargets = [
    "edgenode-01:9100" "edgenode-02:9100" "edgenode-03:9100"
    "edgenode-04:9100" "edgenode-05:9100"
  ];
};

# every node, monitor included
services.holochain-edgenode = {
  metricsExporter.enable = true;
  conductorMetrics.enable = true;
};
```

A conductor with no hApp installed joins no DHT, so its connection and byte counts sit at zero while `holochain_conductor_up` and `holochain_conductor_peer_urls` are already non-zero. That is the correct reading of a bare node, not a broken panel.

### 3. What the Wind Tunnel runner is, and is not

It is not a data source. `holochain-windtunnel` runs `ghcr.io/holochain/wind-tunnel-runner`, whose entrypoint is

```sh
chronyd -q 'server pool.ntp.org iburst' 'makestep 1 -1'
exec nomad agent -config=<baked nomad.json> -config=/etc/nomad.d
```

and whose baked config sets `client.servers = ["nomad-server-01.holochain.org"]`. Both were read out of the pulled image. Enabling the module joins the machine to the Holochain Foundation's Nomad cluster as a client, and the Foundation then schedules Wind Tunnel scenarios, each with its own conductor, onto it. Nothing in the image exposes a Prometheus endpoint: the image config declares no ports, and neither the README nor the repository mentions Prometheus or metrics. That is why `windtunnelTargets` was removed from the Grafana module rather than wired up.

So the module exists as an honest opt-in, a way to donate a spare machine to the Foundation's test network, off by default, with the consequences written into its option description, and the fleet dashboard's traffic comes from our own conductors instead.

The image publishes only the moving tags `latest`, `latest-amd64` and `latest-arm64`, so the module's default pins the multi-architecture index digest that `latest` resolved to on 2026-08-28. Re-pin it with `skopeo inspect docker://ghcr.io/holochain/wind-tunnel-runner:latest`.

## The HTTP gateway

A browser cannot speak the conductor's app websocket protocol, so reading a hApp from a web page means something in front of the conductor that turns an HTTP request into a zome call. That something is `hc-http-gw`, the Holochain Foundation's own gateway, and `modules/holochain-http-gateway.nix` runs it.

The route is one GET per zome function:

```
GET /{dna-hash}/{installed-app-id}/{zome}/{fn}?payload=<base64url of a JSON document>
```

The gateway decodes the payload, transcodes it to msgpack, dispatches the call over an app websocket it opens through the admin API, and transcodes the reply back to JSON. `200` carries the zome's answer, `403` means the app or the function is not on the allow list, `404` means no installed app matches the DNA hash and app id.

### Not the bundled `hc http-gw`

Holonix's `hc` ships an `http-gw` subcommand, and the first design (ADR-009) used it. It was replaced because the bundled build carries whatever gateway version that `hc` was cut with — 0.3.1 in the pinned holonix, on a `hc` from the 0.7 line — while upstream publishes one gateway release per Holochain line and the two are not compatible:

| Holochain | Gateway | Pinned here |
|---|---|---|
| 0.6.x | 0.3.x | `v0.3.5` (holochain_client 0.8.3, holochain_types 0.6.3) |
| 0.7.x | 0.4.x | `v0.4.0` (holochain_client 0.9.0, holochain_types 0.7.0) |

`packages/holochain-http-gateway.nix` builds the tagged source with `rustPlatform.buildRustPackage` and picks the release from the Holochain line, exactly as the network section does. Both are exposed as `packages.<system>.holochain-http-gateway` and `holochain-http-gateway-0_6`, so an operator can check which binary a node would run without evaluating a system.

The build uses the nixpkgs the matching holonix already pins rather than this flake's `nixos-25.05`: the crate's `rust-toolchain.toml` asks for a rustc newer than 25.05 carries, and holonix's is new enough. That adds no input to the lock.

### Nothing is exposed by default

`allowedAppIds` defaults to `[]`, which means the gateway starts, answers `/health`, and refuses every zome-call path. Exposing a function is two facts written down:

```nix
services.holochain-http-gateway = {
  enable = true;
  allowedAppIds = ["dino-adventure"];
  allowedFns.dino-adventure = ["dino_adventure/get_all_dinos_local"];
};
```

The gateway does nothing to tell a read from a write. `allowedFns.<app> = ["*"]` is accepted, because upstream accepts it, and raises an evaluation warning, because it publishes the app's write functions to anything that can reach the port.

### The first call after boot is slow

The conductor compiles a hApp's wasm on its first zome call, and on a cold node that took 54 to 61 s in the VM tests. `zomeCallTimeoutMs` defaults to 10000, so a reader who curls the gateway right after boot may see one 500 before the cell is warm; the second call answers in milliseconds. Wait for `holochain-happ-installer.service` to finish and call once before pointing a demo at it.

### Two implementation details worth knowing

The binary reads its configuration from the environment, and one of those variables carries the app id in its *name*: `HC_GW_ALLOWED_FNS_<app-id>`. systemd rejects an `Environment=` assignment whose name contains a dash, and app ids routinely contain dashes, so the module passes those through `env` in a small launch script and keeps the fixed-name variables in the unit's environment where `systemctl show` can print them.

`hc-http-gw --help` does not work without `HC_GW_ADMIN_WS_URL` set: the program loads its configuration before clap prints anything, and exits with `HC_GW_ADMIN_WS_URL is not set`. The full variable list is in each option's description in [`module-options.md`](module-options.md).

### The test

`vmTestGateway` installs Dino Adventure v0.3.0 on a real conductor, allows exactly one function, and drives the gateway over HTTP. `get_all_dinos_local` is a pure read taking no payload; `get_all_dinos` is its sibling in the same zome, equally a read, and deliberately left off the allow list. The 200 proves the whole path from HTTP to the zome and back; the 403 on a function that exists proves the allow list is what refuses it, not a missing route.

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
