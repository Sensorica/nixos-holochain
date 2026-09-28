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
│   ├── conductor-counters.jq      ← running byte and message totals across closed connections
│   ├── dht-metrics.jq             ← list-apps + dump-network-metrics → per-DHT Prometheus text
│   ├── holochain-grafana.nix      ← optional: Prometheus + Grafana for a fleet
│   ├── holochain-rules.nix        ← the recording rules every dashboard reads
│   ├── holochain-services.nix     ← the services each node runs, by name, for the dashboards
│   ├── dashboards/                ← provisioned Grafana dashboards
│   ├── holochain-windtunnel.nix   ← optional: donate the machine to the Foundation's Nomad cluster
│   ├── holochain-http-gateway.nix ← optional: HTTP gateway in front of the conductor
│   ├── holochain-bootstrap.nix    ← optional: Kitsune2 bootstrap and relay server
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
| `holochain-bootstrap.service` | simple, `DynamicUser`, no state directory | `holochain-bootstrap.enable` |
| `holochain-service-health.service` | oneshot, driven by the timer: runs every declared health check and writes `holochain-service-health.prom` | a health check is declared (the bootstrap server declares one) and `services.holochain-services.textfileDirectory` is set |
| `holochain-service-health.timer` | `OnBootSec` / `OnUnitActiveSec` = 30 s | as above |

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

Four more options add keys only when set, so the default config above is unchanged by them:

| Option | Renders | Lines |
|---|---|---|
| `relayAllowPlainText` | `network.advanced: {"irohTransport":{"relayAllowPlainText":true}}`, merged by the conductor under the keys it sets itself | both |
| `requestTimeoutS` | `network.request_timeout_s` | both |
| `dbSyncLevel` | top-level `db_sync_level` (`Full`, `Normal`, `Off`) | 0.7 only; warned and dropped below it |
| `wasmBackend` | top-level `wasm_backend` (`cranelift`, `LLVM`, `wasmi`) | 0.7 only; warned and dropped below it |

The `edgenodeConfigRender` check renders all four on each line and starts that line's conductor on the result. The holonix 0.7.0 binary is built with cranelift only: given `wasm_backend: LLVM` it exits with "Conductor is configured to use the LLVM WASM backend but this binary does not support it", which is also how that check was shown able to fail.

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

also calls `list-apps` for the installed apps, folds the reply's per-connection counts into running totals with `modules/conductor-counters.jq`, pipes the lot through `modules/conductor-metrics.jq`, and moves the result into `metricsExporter.textfileDirectory` atomically, because the collector may read the directory at any moment.

The service is a thin wrapper around one program, `packages.<system>.holochain-conductor-exporter` (`packages/holochain-conductor-exporter.nix`), which any other conductor on the machine runs too: a Moss node, say, under its own name. It takes the conductor's name, a command that prints the admin port and optionally the allowed origin (a Moss node picks both anew at every start), the names file described below, the textfile to write and a directory for the running totals. Every line it writes carries `conductor`, from `conductorMetrics.name` (default `Holochain`), so two conductors on one machine never merge into one series.

One program matters for a reason that is easy to miss. node_exporter's textfile collector merges every `*.prom` file of its directory by family, and when two files give one family different `# HELP` text it logs `inconsistent metric help text`, keeps the family from the first file only, and sets `node_textfile_scrape_error` to 1: every series of that family in the second file vanishes. So every `# HELP` and `# TYPE` line lives in one place, `modules/families.jq`, which both jq programs `include`, and a family missing from it is an error rather than a line made up on the spot. `checks.metricsHelpAgreement` runs the whole program for an edgenode-shaped conductor and a Moss-shaped one on captured replies, requires every family the two files share to be declared with the same bytes, and then has a real node_exporter read both files and serve every sample line of both, one for one, with `node_textfile_scrape_error 0`. The count matters because node_exporter has a second way to lose a series that leaves the scrape error at 0: a series another file already gave with the same name and labels is dropped with only an `ERROR ... was collected before with the same name and label values` in its log. A family that loses its `conductor` label does that, and so do two conductors on one machine left under the same name, which is why each needs its own `conductorMetrics.name`.

The reply is Kitsune2's `TransportStats` (`kitsune2` `crates/api/src/transport.rs`), wrapped by Holochain with `blocked_message_counts`. It is byte-identical on both lines. Verified against the pinned binaries, on a bare conductor with no app installed and no peers:

```
$ hc client call --port 4471 dump-network-stats            # holochain 0.7.0
{"transport_stats":{"backend":"iroh","peer_urls":["https://use1-1.relay.n0.iroh-canary.iroh.link.:443/57b3f7ba59f9e69714ce3033240108fbffba2f31d1d584df540eb4f8a788a164"],"connections":[]},"blocked_message_counts":{}}

$ hc sandbox call --running 4461 dump-network-stats        # holochain 0.6.3
{"transport_stats":{"backend":"iroh","peer_urls":["https://use1-1.relay.n0.iroh-canary.iroh.link.:443/eee66b1f1962c1132a11638571f477e9c90575f4378c636c81096502db1c9d9c"],"connections":[]},"blocked_message_counts":{}}
```

`dump-network-metrics`, the other candidate the issue named, answers `{}` on a conductor with no app installed, because it reports per-DNA gossip state and there is none. `dump-network-stats` always has something to say, which is why the gauges are derived from it.

Each entry of `connections` carries `pub_key`, `send_message_count`, `send_bytes`, `recv_message_count`, `recv_bytes`, `opened_at_s` and `is_direct`. These are the series derived from them, each labelled `conductor`:

| Series | Type | Meaning |
|---|---|---|
| `holochain_conductor_up` | gauge | 1 when the admin interface answered, 0 when it did not |
| `holochain_conductor_peer_connections` | gauge | Transport connections currently held |
| `holochain_conductor_direct_peer_connections` | gauge | Of those, the ones that upgraded off the relay |
| `holochain_conductor_peer_urls` | gauge | Peer URLs this conductor can be reached at |
| `holochain_conductor_network_sent_bytes_total` | counter | Bytes sent, kept as a running total across connections that have closed |
| `holochain_conductor_network_received_bytes_total` | counter | Bytes received, kept as a running total across connections that have closed |
| `holochain_conductor_network_sent_messages_total` | counter | Messages sent, kept as a running total across connections that have closed |
| `holochain_conductor_network_received_messages_total` | counter | Messages received, kept as a running total across connections that have closed |
| `holochain_conductor_blocked_messages_total` | counter | Messages blocked in either direction, summed over every block reason |
| `holochain_conductor_apps{conductor, status}` | gauge | Installed apps by status type from `list-apps`; `enabled` and `disabled` always present, absent when `list-apps` did not answer |
| `holochain_conductor_metrics_scrape_timestamp_seconds` | gauge | When the textfile was last written |

Two properties are worth stating explicitly:

- **A down conductor reports `holochain_conductor_up 0`, it does not disappear.** The script writes the file whether or not the call succeeded, so a dead node is visible on the dashboard rather than absent from it. This is the difference between a panel that says "one node is down" and a panel that quietly draws four lines instead of five.
- **The byte and message counters only go up.** The reply counts per open connection, so its plain sum drops whenever a peer disconnects, and `rate()` reads any drop as a counter reset: it would draw the whole remaining total as a burst of traffic that never happened. So the timer keeps the counts it last saw per connection, keyed by `pub_key` and `opened_at_s`, and the running totals, in `conductor-metrics-counters.json` under the conductor's `dataDir`, and adds each connection's growth since the previous run (`modules/conductor-counters.jq`). What a connection moves between the timer's last look and its closing is not counted, so the totals undercount by at most one interval of a closing connection. Losing the state file restarts them from zero, which Prometheus handles as the reset it is.

#### Per-DHT series

`dump-network-stats` is transport-wide: it cannot say which app network a peer or a byte belongs to. Once an app is installed, `dump-network-metrics --include-dht-summary` can, so the same timer also runs

```
hc client call --port 4444 dump-network-metrics --include-dht-summary        # 0.7
hc sandbox call --running 4444 dump-network-metrics --include-dht-summary     # 0.6
```

and passes its reply, with the `list-apps` reply, to `modules/dht-metrics.jq`. The reply is keyed by DNA hash; each entry has a `fetch_state_summary` (`pending_requests`, one entry per operation asked of a peer and not yet received) and a `gossip_state_summary` whose `peer_meta` holds, per peer URL, `last_gossip_timestamp` in microseconds, `completed_rounds`, `peer_timeouts` and the peer's own `dht_op_count`, next to `local_op_count` for this node. Kitsune2 declares these structs identically in `kitsune2_api` 0.4.1 and 0.5.0, and the fixtures under `tests/fixtures/dht-0_6_1/` are both replies as a Holochain 0.6.1 conductor in seven DHTs gave them (a Moss group node, network seeds redacted). The homelab's Holochain 0.6.3 edgenode conductor, with three apps in four DHTs, gave the second pair of fixtures, under `tests/fixtures/edgenode-0_6_3/`. `list-apps` names the app and role each DNA belongs to, so every series carries `conductor`, `app_id` (the installed_app_id), `role` and `dna`, and nothing else: machine keys only.

| Series | Type | Meaning |
|---|---|---|
| `holochain_dht_peers` | gauge | Peers this conductor keeps gossip state for in the DHT (entries in `peer_meta`) |
| `holochain_dht_local_ops` | gauge | DHT operations held here (`local_op_count`) |
| `holochain_dht_peer_ops` | gauge | The largest `dht_op_count` any peer reported; `local_ops` reaching it means this node holds as much as its best peer |
| `holochain_dht_pending_fetches` | gauge | Operations asked of peers and not yet received |
| `holochain_dht_seconds_since_gossip` | gauge | Seconds since the latest `last_gossip_timestamp` over all peers; -1 when there is none |
| `holochain_dht_completed_rounds_total` | counter | `completed_rounds` summed over the peers currently in `peer_meta` |
| `holochain_dht_peer_timeouts_total` | counter | `peer_timeouts` summed over the same peers |

The two counters are sums over the peers the conductor still knows, so forgetting a peer lowers them, which `rate()` reads as a reset; they are exported as the conductor keeps them rather than folded into running totals the way the byte counters are.

#### Names

No hash, loopback port or role id is meant to reach a screen, and a rename must never split a data series. So names travel apart from the data, on two info families whose value is always 1, written by the same program and joined at query time:

| Series | Labels |
|---|---|
| `holochain_app_info` | `conductor`, `app_id`, `app_name`, `app_kind`, `status` (the `list-apps` status, or `expected`) |
| `holochain_dht_info` | `conductor`, `app_id`, `role`, `dna`, `app_name`, `app_kind`, `part_name`, `network_label` |

Everything that knows a name puts it in a JSON file the program reads as the third document on the jq's stdin, so this program stays the only writer of both families:

```json
{
  "apps": {
    "requests-and-offers": { "name": "Requests & Offers", "roles": { "requests_and_offers": "Listings", "hrea": "Accounting" } },
    "applet#uhc$e$k...": { "name": "General chat", "kind": "Vines" }
  },
  "kinds": { "Vines": { "rVines": "Messages", "rFiles": "Files" } },
  "expected": ["hrea", "kando", "requests-and-offers"]
}
```

`holochain_dht_info` has exactly one row per `conductor`, `app_id`, `role` and `dna`, the full key of every `holochain_dht_*` series, so a query that joins names onto data must match on all four (and `instance`): `* on (instance, conductor, app_id, role, dna) group_left (network_label) holochain_dht_info`. A join on fewer is a many-to-many error as soon as an app has a clone cell, because a clone shares its conductor, app id and role with the cell it was cloned from and differs only in its DNA; Prometheus then fails the whole query, not only the clone's line.

The edgenode module writes the file from each app's `displayName` and `roleNames`, and lists in `expected` every app it manages with `installed = true`. An app's `kind` is read only when the app is expected and `list-apps` does not report it, since its bundle, where the kind otherwise comes from, is then unknown; a Moss wrapper that lists the tools it has seen as expected passes each one's kind with it. What a name falls back to when nobody gave one:

- **`app_name`**: the bundle's name from `list-apps`, underscores and dashes read as spaces and the first letter capitalised (`requests_and_offers` reads "Requests and offers"). A Moss tool (`applet#...`) takes its kind instead, and a Moss group (`group#...`) reads "Group". An expected app nobody listed takes its id prettified, except a Moss app, which takes its `kind` from the names file, else "Group" or "Tool", never its id, which is a hash. Two apps that would read alike, the two chats of one Moss tool for instance, are numbered in the order of their installed_app_id ("Vines 1", "Vines 2"). A given name can still match another app's name; the two are then numbered too, the given name keeping its own ("Kando" and "Kando 2"). No two apps of one conductor share a name, and a hash is never how two of them are told apart.
- **`app_kind`**: for a Moss app, the bundle's name without the "h" before a capital (`hVines` reads "Vines"), or "Group", or for a Moss app nobody listed, the names file's `kind`, else "Group" or "Tool"; for any other app, its `app_name` again.
- **`part_name`**: the app's own `roles` entry, then the `kinds` table for the app's kind, then nothing when the app has a single role (its network then reads by the app's name alone, "Kando" rather than "Kando: Kando"), and otherwise the role id with a one-letter prefix dropped (`rFiles` reads "Files"), or "Main" when that would only repeat the app's name or kind ("Group: Main" rather than "Group: Group"). A clone cell adds its clone index, counted from 1 ("Messages (clone 1)", or "Clone 1" for a one-role app), from its `clone_id`, else from its place among the role's clones.
- **`network_label`**: `app_name` alone for a one-part app, else "app_name: part_name". No two DHTs of one conductor share one.

An app in `expected` that `list-apps` does not list, or every expected app when `list-apps` did not answer, is still written to `holochain_app_info`, with `status="expected"`, so a dashboard can show it as not running instead of losing it. A names file that is missing or of the wrong shape costs the names, never the series. `checks.metricsNameShape` fails when any `app_name`, `app_kind`, `part_name` or `network_label` the program writes for the two fixture conductors, the Moss one also stopped with its apps only expected, contains `$` (Moss's case escape) or `uhC` (a hash) anywhere, or a run of twenty or more id characters without a space anywhere in it.

What happens when something goes wrong is chosen so that it costs only these series. Either call failing writes no `holochain_dht_*` line at all, rather than zeros that would read as a DHT with no peers; a cell whose DNA the reply does not list is skipped for the same reason. Label values are escaped, since an app id is free text and one unescaped quote would make node_exporter drop the whole file. And the script appends the jq output only when jq exits cleanly, so a reply of an unexpected shape loses the DHT series for that run and never the conductor series. Both replies reach jq on stdin rather than as `--argjson`: a `list-apps` reply carries every DNA's properties, the Moss node above answers 110 KB for three apps, and Linux caps a single command-line argument at 128 KiB.

`checks.dhtMetricsJq` runs the jq on both pairs of captured replies and checks the numbers of one DHT by hand, the names with no names file, with a Moss-shaped one and with a hand-typed one in the shape the edgenode module writes, that every data series has exactly one info row with its key, that no two apps or DHTs of one conductor share a name, and that names never change a data line; then a stopped Moss conductor whose apps are only expected, given names that match other apps' names, each call failing, an empty network, `list-apps` not answering while apps are expected, names files of the wrong shape, and an app id and a conductor name with a quote, a backslash and a newline in them next to stem, cloned and unlisted cells and fields of the wrong type, passing every output through `promtool check metrics`. `checks.edgenodeNamesWiring` covers what that hand-typed file cannot: it evaluates a system with the edgenode module, `displayName`, `roleNames`, an app with `installed = false` and a `conductorMetrics.name` with a space in it, runs the metrics unit's own script with the exporter swapped for one that prints its arguments, and feeds the names file it points at through the jq with the captured edgenode replies. `vmTestWithHapp` and `vmTestWithHapp-0_6` install a real hApp and assert that every cell `list-apps` reports has its seven series on `/metrics` and one `holochain_dht_info` row, with 0 peers and -1 seconds since gossip on a node that is alone on its network.

### 2. Prometheus and Grafana

`holochain-grafana` runs both on the monitor node and provisions the pair that makes a dashboard work without a human: a Prometheus data source with the fixed uid `holochain-prometheus`, and every JSON file under `modules/dashboards/`.

#### Five dashboards, one question each

The shipped dashboards are built around who reads them and what that reader asks, and each is titled with the question. All five are tagged `holochain` and link to one another.

| uid | Title | Reader |
|---|---|---|
| `holochain-home` | What is this machine running? | Anyone opening Grafana: it is Grafana's home page, and opens on the machine Grafana runs on |
| `holochain-now` | Is the Holochain network working? | The room, on a shared screen in kiosk mode |
| `holochain-fleet` | Which Holochain node needs attention? | Whoever runs the fleet |
| `holochain-node` | Is this node working, app by app? | An operator with one machine, or a link from the fleet page |
| `holochain-network` | Is this app in step on every node? | The facilitator asked whether a message reached the others, or the operator after a Lost contact |

The home page says what one machine runs, in words: its state, host name, NixOS release, kernel, how long it has been up and how busy its processor, memory and fullest disk are; then every service it runs, worst first, with its state, the version of what it runs and when it last started; then its Holochain conductors, each with the service that runs it, its Holochain version and whether it answers, and every app on them in the six state words. A node picker shows any machine of the fleet, and links lead to the fleet, node, network and room pages and, where the Moss module provisions one, to the Moss page. The room screen answers in plain words: whether its readings are current, one tile per machine, a matrix of app by machine in the six state words, how many others each app sees, a step chart of the data each machine holds in the room's app (a write steps every line up together), and how long since each app last heard from anyone. The fleet page counts what is wrong across the fleet, lists the machines worst first, names every problem in a sentence, lists the watched services that are down, and keeps machine health in a collapsed row. The node page takes one machine part by part, lists every service it runs by name with its state, and keeps its machine health and network traffic in collapsed rows. The network page takes one app network, chosen by its name, across every machine.

The pages never name a series by a machine key. Legends, display names and table columns use only labels a person reads (`node`, `site`, `conductor`, `app_name`, `app_kind`, `part_name`, `network_label`, a `problem` sentence, a unit and its state mapped to words, a disk's mount point, a sensor, the machine's host name, system and kernel release, and the `version` and `holochain_version` a service declares), every table keeps an explicit list of its columns, no stat picks a key as its field, no title, description or legend shows a variable whose value is a key (the network page names its network in the dropdown, by its label, never by the DNA hash the variable holds), and every panel carries a description of the question it answers. The one exception is the collapsed "For bug reports" row of the network page, which shows the node, conductor, installed app id, role and DNA hash of one network, to paste into an issue. No variable carries an app id: Moss ids contain `$`, which Grafana would read as a variable, so the network page keys on the DNA and shows its name. `checks.dashboardLabels` holds the JSON to all of this.

The service tables read the rule `holochain:service_state`, described under [Services, from what each node runs](#services-from-what-each-node-runs), which rests on `node_systemd_unit_state`: node_exporter's systemd collector exports it for every unit on the node except device, scope and slice units, and both modules pass `--collector.systemd.unit-exclude` so that mount units, which node_exporter leaves out by default, are counted when they fail. The module rewrites a few things into each provisioned dashboard on its way into the store, because the JSON is read-only once there and a browser edit would not survive a rebuild; everything else reaches Grafana untouched. For a dashboard of your own, a `units` textbox variable takes the `overviewUnits` keys as its default, and a field override on `name` takes their names as value mappings (the shipped pages have neither: they read the rules). The room constants are described below, and the state thresholds here. A threshold step whose `fromOption` key names a `states` option (the readings age, the silence before Lost contact, the in-step share) takes that option's value, the plain steps beside it are clamped so the steps stay in order, and the sentences that quote a threshold ("more than 90 seconds old", "at least 95%", "in the last 24 hours") quote the value given, so a page never colours a part amber while its word says In step. For a dashboards directory in the store, the module also sets Grafana's `default_home_dashboard_path` to a copy of the rewritten `holochain-home.json`, whose `node` variable the rewrite defaults to this machine (the name of a scrape target on a loopback address, else `networking.hostName`), so `/` opens on the machine Grafana runs on; a directory without it falls back to `holochain-now.json`, with its room constants, and one with neither to a copy of Grafana's own home page, since Grafana answers a home path that does not exist with an error. The copy is chosen while building, never by looking into the directory while evaluating, so a directory inside a package does not have to be built first and the module evaluates where import-from-derivation is off.

#### Node names

Every node goes by a name, which Prometheus attaches to every series it scrapes from the node as the `node` label, next to `instance`; a `site` label joins it when one is given. The name comes from `scrapeTargets`, rendered as one static config per target. As an attribute set, the key is the name and the value gives the `address` and, optionally, the `site`:

```nix
scrapeTargets = {
  homelab = { address = "127.0.0.1:9100"; site = "Soushi home"; };
  lab-1 = { address = "sensorica-holoport-01:9100"; site = "Sensorica lab"; };
};
```

As a plain list of `host:port` strings, which is what the option took before, each node is named after the host part of its address, and a loopback address (127.0.0.1, localhost, ::1) takes the monitor's `networking.hostName`. A list entry given by an IP address therefore goes by that address on every dashboard, and evaluation warns about each such entry, pointing at the attribute set form. Because the name comes from the target, a node that is down still has one. Two targets that would go by one name are refused at evaluation, since every dashboard aggregates by `node` and would read them as one machine; two ports on one loopback need the attribute set form. No exporter writes a `node` label of its own: with `honor_labels` off, Prometheus would keep the target's and rename the exporter's to `exported_node`.

#### States, computed once

The dashboards never compute a state themselves. `modules/holochain-rules.nix` holds one group of Prometheus recording rules, which the module renders with its `states` options and hands to Prometheus as a rule file, evaluated at every `scrapeInterval`; `promtool check rules` runs on the file when the system is built. Every state is a code ordered from worst to best, so `min` over any set picks the worst item:

| Code | DHT or app | Meaning |
|---|---|---|
| 0 | Not running | The app should be installed here and Holochain does not report it |
| 1 | No fresh readings | The conductor's readings are older than `states.staleAfterSeconds` (90) |
| 2 | Lost contact | Nobody is connected, although somebody was within `states.historyWindow` (24h) or another node of the fleet runs the same DNA; or peers are known and nothing was heard from them for `states.silentAfterSeconds` (600) |
| 3 | No one else yet | Nobody is connected, nobody was, and no other node of the fleet runs the DNA: normal for a node that is alone |
| 4 | Catching up | Connected, holding less than `states.inStepShare` (0.95) of the best peer's data on average over `states.shareWindow` (10m) |
| 5 | In step | Connected, and holding at least that share |

A conductor is 1 Holochain not answering, 2 No fresh readings or 3 Running. A service (below) is 0 Failed, 1 Stopped, 2 Not answering, 3 No fresh readings, 4 Starting, 5 Stopping or 6 Running. A node is 0 Unreachable, 1 Holochain not answering, 2 A service is down (failed, stopped or not answering), 3 No fresh readings (a conductor's readings or a service's health reading), 4 Running or 5 No Holochain here: unreachable wins, then the worst of its conductors and services, and a machine with neither a conductor nor a service down reads No Holochain here. A service that is down ranks above a reading that is old, because systemd's word on the service is fresh, so a stale reading cannot hide a failed gateway, and the colours only get better from one code to the next (red, red, red, orange, green, grey). Starting and Stopping leave the node as it is, since a restart passes through them; a service that keeps failing while systemd restarts it reads Failed, not Starting (see below). A healthy DHT never holds everything its best peer holds, since new data is always on its way: the Sensorica Moss node's DHTs held between 94% and 99% on 2026-09-27. Hence a share of 0.95 averaged over ten minutes rather than an instantaneous 1, and both are options to recalibrate on a real fleet.

The history behind Lost contact is kept per full DHT key, so it starts afresh whenever the labels of a DHT's series change, as they do when a node switches from an exporter that wrote other labels to this one. For up to `states.historyWindow` after such a switch, a DHT that lost its peers before it reads No one else yet rather than Lost contact, unless another node of the fleet runs its DNA. Switching while the DHTs have peers avoids the gap.

| Series | What it is |
|---|---|
| `holochain:dht_state`, `holochain:app_state:named`, `holochain:conductor_state`, `holochain:node_state` | The states above, per DHT, per app (its worst DHT), per conductor and per node |
| `holochain:dht_names` | `holochain_dht_info`, or for a DHT without an info row a fallback named "Unnamed app", its part named after its role id the way the exporter prettifies one ("rFiles" reads "Files", "requests_and_offers" reads "Requests and offers"), so it is still drawn and counted |
| `holochain:dht_state:named`, `holochain:dht_peers:named`, `holochain:dht_share:named`, `holochain:dht_heard:named`, `holochain:dht_missing:named` | Per-DHT series with the names joined on, for display; "heard" turns the -1 of never into 1e9, the longest silence there is |
| `holochain:dht_share`, `holochain:dht_share_raw` | The share of the best peer's data held here, only while there is a peer |
| `holochain:dna_nodes`, `holochain:dna_same_data`, `holochain:dht_had_peers`, `holochain:conductor_fresh` | The inputs of the ladder, kept for panels that need them |
| `holochain:service_watched`, `holochain:service_state` | The services watched on each node, one series per unit with its name in `service`, and the state of each; a conductor no watched unit claims is a service of its own, "Holochain conductor (<conductor>)" |
| `holochain:node_problem` | One series per thing a human must act on, its sentence in the `problem` label: each failed unit, watched or not, by its watched name or else its unit name ("Holochain conductor has failed"), and likewise each unit that keeps failing while systemd restarts it ("Local bootstrap and relay failed and systemd is restarting it"), a watched service that is stopped, does not answer or has an old health reading ("Local bootstrap and relay is not answering", "Local bootstrap and relay readings are over 90 s old"; a service that runs a conductor is left to the conductor's own sentences), a disk or memory over 90%, a sensor over 85 °C, a metrics file node_exporter could not read, a conductor not answering or with old readings (named in brackets, except the default "Holochain", which reads "Holochain is not answering"), app parts with no name |

Every join of names onto data matches on the full key of a DHT (`instance, conductor, app_id, role, dna`), for the reason given under [Names](#names): a clone cell makes any shorter key many-to-many. Counts that colour a panel read the raw-keyed rules, so a DHT whose name is missing still counts. `checks.holochainRules` runs `promtool test rules` on the rendered file: a node alone, three nodes in step and catching up, contact lost after having peers, on a DNA another node runs, and to silence, readings that stop, the homelab's two conductors on one instance as the exporter writes them for the captured replies (`tests/fixture-textfiles.nix`, at the capture's own clock so the gossip ages are the captured ones), an app Nix expects and Holochain does not list, DHTs with no name, node states, conductors under the default name, a machine in trouble, a healthy machine just under every threshold with a full tmpfs, which must raise no problem, and every service state in words with what each does to its node (a conductor unit active while its conductor does not answer, a Moss conductor no unit claims, a claimed conductor not listed twice, the readings of a claimed and of an unclaimed conductor gone old, a conductor under the default name, a stale health reading, a stopped service beside old readings), and, scraped every 15 s, services that keep failing while systemd restarts them, caught between two tries or in the moment they are up, against one restarted once and back up and one starting that was never restarted. A second rule file, rendered with `overviewUnits` set, must watch those units on the nodes that run them, by their names or unit names, while a node's own name for a unit wins. It then breaks every expectation of both on its own and requires promtool to fail on each.

#### Services, from what each node runs

No list of services is kept by hand. Every nixos-holochain module imports `modules/holochain-services.nix` and, when it is enabled, adds the units it creates to `services.holochain-services.units`, each with the name a person reads; on a machine where any of them is enabled, the services beside them that are enabled there join the list too. Each node publishes its own list through node_exporter's textfile collector, as `holochain-services.prom`, a link into the store refreshed on every activation, with one `holochain_service_info{name, service, version}` line per unit (and `conductor` and `holochain_version` for a unit that runs a conductor), so a monitor learns what a Holoport runs, and in which version, from the Holoport and not from its own configuration. Prometheus attaches the node's name as it does to any series. The rule `holochain:service_watched` takes that list, plus any unit the monitor's `overviewUnits` adds, and `holochain:service_state` gives each its state:

| Service, as the pages name it | Unit | Listed when | Health reading |
|---|---|---|---|
| Holochain conductor, or "Holochain conductor (Workshop)" under `conductorMetrics.name = "Workshop"` | `holochain-conductor.service` | `holochain-edgenode.enable` | its conductor's readings: Not answering when the admin interface does not answer, No fresh readings when they are old (`conductorMetrics`) |
| App installer | `holochain-happ-installer.service` | `happs != {}` | none; a one-shot that remains active once done |
| Holochain readings (timer) | `holochain-conductor-metrics.timer` | `conductorMetrics.enable` | none; the service sits idle between runs, the timer stays active |
| HTTP gateway | `holochain-http-gateway.service` | `holochain-http-gateway.enable` | none |
| Local bootstrap and relay | `holochain-bootstrap.service` | `holochain-bootstrap.enable` | `/health` every 30 s, on its first listen address or the loopback for a wildcard |
| Wind Tunnel runner | `podman-wind-tunnel-runner.service` (or `docker-`) | `holochain-windtunnel.enable` | none |
| Metrics database | `prometheus.service` | `holochain-grafana.enable` | none |
| Dashboards | `grafana.service` | `holochain-grafana.enable` | none |
| Machine readings | `prometheus-node-exporter.service` | node_exporter enabled | none |
| Remote login | `sshd.service`, or `sshd.socket` with `startWhenNeeded` | `services.openssh.enable` | none |
| Private network (Tailscale) | `tailscaled.service` | `services.tailscale.enable` | none |
| Nix | `nix-daemon.socket` | `nix.enable` (the socket, since the daemon starts on demand) | none |
| "Holochain conductor (<conductor>)", for example "Holochain conductor (Moss)" | none | a conductor whose readings reach this node_exporter and that no listed unit claims | its readings, as for the conductor above |

A service reads, worst first, Failed, Stopped, Not answering (the unit is active but its health check fails, or the conductor it runs does not answer), No fresh readings (its last health reading, or its conductor's readings, older than `states.staleAfterSeconds`), Starting, Stopping, or Running. Failed covers a unit that keeps failing while systemd restarts it: with `Restart=` and a `RestartSec`, as the bootstrap server has (on-failure, 5 s), systemd reports such a unit as activating between two tries and never as failed, so the rule reads node_exporter's restart count (`node_systemd_service_restart_total`, which the edgenode and grafana modules turn on with `--collector.systemd.enable-restarts-metrics`): restarted in two scrapes within `states.staleAfterSeconds`, or in one and not up yet, is Failed. Each shows in three places. The node page's "Is each service on this machine running?" lists every one of that machine, worst first. The fleet page's "Which services are not running?" lists the ones that are not Running on every machine. The room screen's tile for the machine reads "A service is down" while one is Failed, Stopped or Not answering, and "No fresh readings" while one's reading is old; for each of those the fleet page's problem list names the service in a sentence, and the room's "Are these readings current?" and the fleet's Stale readings and Oldest reading count health readings as well as conductors'. A unit a node lists but does not run has no row at all, since node_exporter has no state for it, so evaluation warns about a listed service, socket or timer the configuration does not define.

Each module gives the unit it lists the version of the package it runs it from, as `version`, and a unit that runs a conductor also the Holochain that conductor is, as `holochainVersion`: the conductor its edgenode `package`'s version for both, the app installer its `hcPackage`'s, the HTTP gateway and the bootstrap server their `package`'s, Prometheus, Grafana, node_exporter, sshd, Tailscale and the Nix daemon theirs, and a Moss node wdocker's with the Holochain wdocker brings (`passthru.holochainVersion` of the `wdocker` package), which can differ from the edgenode's. Nothing is asked of a running service, so the version shown is the one the machine was built with. The readings timers and the Wind Tunnel runner, whose container is pulled by digest, declare none, and a unit a configuration lists without one publishes no `version` label, which the home page shows as a dash. The labels ride through `holochain:service_watched` into `holochain:service_state`, so the home page reads a service's state and version from one series. When a unit last started comes from node_exporter's `node_systemd_unit_start_time_seconds`, which both modules turn on with `--collector.systemd.enable-start-time-metrics` (zero for a unit that is not active, and left blank on the page).

The health reading exists for the bootstrap server because the 0.4.1 server can stay active while it listens on nothing (see `listenAddresses`), so its unit's state alone would say Running. A timer, `holochain-service-health`, runs every check declared in `services.holochain-services.healthChecks` and writes `holochain_service_healthy` (1 or 0) and the time it ran, as root with no capability but the one that lets it write into a textfile directory another user owns.

Nothing is written unless `services.holochain-services.textfileDirectory` names the directory node_exporter reads. The edgenode module sets it when its `metricsExporter` is on, and the grafana module on a monitor, whose node_exporter defaults now include the textfile collector. A machine that runs only the bootstrap server, with a node_exporter of its own, sets it by hand; until then its services are missing from the pages. A conductor another program runs needs no unit listed, once its readings carry a `conductor` label: athanor's Moss node will show as "Holochain conductor (Moss)" after athanor runs it through `holochain-conductor-exporter` with conductor "Moss" (step A1 of the dashboards design). Its current exporter, `moss-node-metrics.jq`, writes `holochain_moss_node_up` and no `conductor` label, so until then the Moss node has no row among the services.

#### Service names and the room

`overviewUnits`, on the monitor, adds units to watch on every node that runs them, on top of the ones each node lists, each with the name a person reads for it; a plain list still works, its units shown by their unit names, and a node's own name for a unit it lists wins. Its default is empty. The rule file renders its keys into `holochain:service_watched`, anchored the way Prometheus anchors `=~`, so an entry such as `restic-backups-.*` names every unit it matches. For a dashboard of your own, every field override matched by name to `name`, the unit label of `node_systemd_unit_state`, gets one regex value mapping per named unit on its way into the store, and a `units` textbox variable gets the keys as its default. The `room` option (`app`, `part`, `label`) sets the constant variables `room_app`, `room_part` and `room_label` of any dashboard that declares them, for a room screen that follows one app's writes; left null, those variables keep their dashboard's own defaults. `checks.grafanaProvisioning` evaluates monitor systems and reads what the module renders: the labels of list and attribute set targets, the refusal of two targets sharing a name, a rule file with states other than the defaults, the shipped dashboards under other states (every marked step moved, no sentence quoting a default) and unchanged under the defaults, the rewrite of a fixture dashboard (`tests/fixtures/dashboards/rewrite.json`), the versions every module declares for its units, compared with the packages they run, and the published list, which must carry each as a `version` (and a conductor's as a `holochain_version`) label, checked again on copies with one label removed, which must fail by the unit's name; and the home page: the shipped "What is this machine running?" for the default directory, opening on the loopback target's name or the host name, the room screen for a copy without it, Grafana's own for a directory with neither, and a home path, with nothing built, for the directory of a package whose build always fails. A copy without the home page and a copy whose home page lost its uid must each fail the home page check.

`vmTestGrafana` runs the whole path in one VM, scraping its own node_exporter and a second target nothing listens on. Its edgenode installs one hApp, so the conductor is in DHTs; the test requires each of them named by its `network_label` and never by a key. It waits for the conductor, asserts `holochain_conductor_up{conductor="Holochain"} 1` appears on `/metrics`, asserts the live target is up and the dead one down, and asserts Prometheus kept the series. It then asserts that Grafana's search for the `holochain` tag returns exactly the five dashboards and that the same test fails on a search cut to four, that its home page is `holochain-home`, opening on `machine`, and that the same test fails on the room screen's answer, and that the data source is there; reads the five back from Grafana's API and checks that the room constants carry the `room` option, that the node page's own `label_values` definition finds both nodes by name, and that the state words and colours (six for an app, six for a node, three for a conductor, seven for a service on all three service tables) reached the panels that show them. Before the conductor fails, the test names its two targets (`machine`, with a site, and `unplugged`) and requires every target to carry its node label; it then writes two more conductors, Workshop and Moss from `tests/fixture-textfiles.nix`, as textfiles beside the live conductor's, and requires node_exporter to serve all of their DHT series with `node_textfile_scrape_error` at 0, Prometheus to report every rule of the file loaded, evaluated, healthy and without an error, `holochain:node_state` to read 3, A service is down, for `machine`, whose `always-fails.service` (added through `overviewUnits`) has failed, and 0 for `unplugged`, the services of `machine` to be exactly the ones its modules installed by their names, the two `overviewUnits` adds by their unit names, and the two fixture conductors no unit claims, the Moss one as "Holochain conductor (Moss)", every service its modules list with a version to carry it as a label, the conductor's own being its package's for both `version` and `holochain_version`, the Moss DHTs to read In step for the connected chat and the group and No one else yet for the chat nobody else opened, the live app to read No one else yet, and the node's problems to be exactly two sentences, one for each unit that always fails, the watched one and one no panel watches, each by its unit name. With the three conductors present, it posts every panel target of the five dashboards to Grafana's `/api/ds/query`, the way Grafana's own panels query, with the variables filled (All, the node, the connected Moss chat for the network page, the rewritten room constants), and requires each to come back without an error and with at least one frame holding a value. Exactly three may be empty and must still not error, and the log counts them apart from the answered ones: the two temperature panels, since a VM has no sensor (the hwmon collector is required to run instead), and "Same data everywhere", which needs two nodes on one network. A query with an `or vector()` fallback answers whatever its left side reads, which is why `checks.dashboardQueries` also requires every series a query reads to be there. The same test on a query that cannot answer must fail. It also checks that every label a query matches negatively exists on its metric, since a misspelled one would match everything, and that mount units are exported. The fixtures are then removed and the conductor's failures are exercised for real: its metrics timer stopped, then the conductor stopped with the timer writing again, then its textfile corrupted, with the node page's Conductors query required to read No fresh readings and then Not answering, the fleet page's problem list to name each in its sentence ("Holochain readings are over 90 s old", "Holochain is not answering", "A metrics file could not be read"), and the room screen's readings tile to read No readings. Finally it fails on any provisioning error in Grafana's journal.

A VM runs one conductor, so what two conductors on one instance do to the pages is `checks.dashboardQueries`, which needs no VM: promtool loads the rendered rule file and runs every Holochain query of the five dashboards, variables filled, on the exporter's output for an edgenode-shaped and a Moss-shaped conductor on one instance, plus a third conductor with a clone cell, which shares its conductor, app id and role with the cell it came from. Every query must answer ("Same data everywhere" excepted, which needs two nodes). Answering is not enough for the twelve queries that end in `or vector(0)` or `or vector(1e9)`, which answer whatever their left side reads, so every series selector a query reads, with its positive matchers (`tests/query-selectors.jq`), must also select something, and every rule a query names must be recorded by the rule file; "Same data everywhere" is held to the second only. The node page's part table must have one row per DHT, the clone included, except Holds, only for the parts with a peer, and Last heard, which leaves out the parts nobody else runs yet; with the Moss conductor stopped, the fleet page's node Status and the room screen's machine tile must read Holochain not answering, the node's worst conductor, and the node page's services "Holochain conductor (Moss)" Not answering. The node lists three services in the fixtures, a conductor that claims Workshop, a stopped HTTP gateway and a bootstrap server with a fresh health reading: "Is each service on this machine running?" must name exactly those and the two conductors no unit claims ("Holochain conductor (Moss)", "Holochain conductor (Clones)"), the fleet's list of services down must hold the gateway alone, and the machine tile must read A service is down. The conductor and the gateway carry versions in the fixtures and the bootstrap server none: the home page's services table must show each service with its version, a dash for the bootstrap server and the unclaimed conductors, and its conductors table one row per conductor, Workshop with the unit that runs it and its Holochain, Moss and Clones with dashes. It then breaks the queries one fault at a time and requires each to fail: a misspelt rule, in an ordinary query, behind a vector fallback, and in "Same data everywhere"; a misspelt metric and a label filter that selects nothing, both behind a vector fallback; the services table reading the watched list instead of the states; the home page's services table losing its versions, and its conductors table joined so that a claimed conductor has two rows; and the part table joined on fewer labels than the full key, which must fail with a many-to-many error. `checks.dashboardLabels` runs its jq over the JSON, then over copies broken one fault at a time (a legend or display name showing a key, a display name showing every label at once through `${__field.labels}`, a title showing a variable whose value is a key, a stat picking a key field, a query without a legend, a panel without a description, a table that keeps every label or shows a key column, the services tables of the node and home pages among them, a home page panel without a description, two dashboards on one uid, the home page among them), and requires each to fail for its reason. `checks.dashboardWords` reads each stand-in value the way Grafana resolves it through a field's mappings, in order: 1e9 on the readings tile reads "No readings" in red, 1e9 on the three Last heard panels reads "never" in red, an empty Last heard or Holds cell on the node table reads "nobody else yet" or "nobody to compare" in grey, and a real figure stays a figure; copies with the range dropped, "never" recoloured, the empty-cell word dropped, or a range that swallows real figures must each fail.

`vmTestServices` runs one machine with an edgenode, the HTTP gateway, the local bootstrap and relay, and Grafana watching itself, and reads what a person reads through Grafana's `/api/ds/query`, with the queries the pages serve. The node page's "Is each service on this machine running?" must name exactly the services the enabled modules installed, by their names, each Running, and the room screen's tile for the machine must read Running; the comparison is first run on answers one service short, one in another state and one too many, and must fail on each. The bootstrap server is then frozen with `SIGSTOP`: its row must turn to Not answering while `systemctl is-active` still says active, the fleet page must list it as down, the problem list must say "Local bootstrap and relay is not answering", and the tile must read A service is down; each of those checks is first required to fail while the server answers. Thawed, it must read Running again; stopped, Stopped, with "Local bootstrap and relay is stopped" and the tile at A service is down. Last, a runtime drop-in makes it exit 1 at every start, so systemd restarts it every five seconds and reports it activating in between: it must read Failed, with "Local bootstrap and relay failed and systemd is restarting it", its `NRestarts` above 1 and the tile at A service is down, the sentence first required to be absent while it is merely stopped. `vmTestServices-noBootstrap` is the same machine without the server: the services are the same less that one, no unit of it exists and no health reading is published. Two falsifiers in `legacyPackages.falsifiers` run the test expecting the server where it does not run and not expecting it where it does; both must fail.

A fleet is the monitor node naming its peers and every node exporting:

```nix
# the monitor node
services.holochain-grafana = {
  enable = true;
  openFirewall = true;
  # named sensorica-holoport-01 to sensorica-holoport-05 after their hosts; an attribute set
  # names them otherwise and gives each a site
  scrapeTargets = [
    "sensorica-holoport-01:9100" "sensorica-holoport-02:9100" "sensorica-holoport-03:9100"
    "sensorica-holoport-04:9100" "sensorica-holoport-05:9100"
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

It is not a data source. Its only trace on the dashboards is one line among the node's services, "Wind Tunnel runner", saying whether its container runs. `holochain-windtunnel` runs `ghcr.io/holochain/wind-tunnel-runner`, whose entrypoint is

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

The build uses the nixpkgs the matching holonix already pins rather than this flake's own nixpkgs, so the gateway shares the conductor's toolchain; this started because the crate's `rust-toolchain.toml` asked for a rustc newer than nixos-25.05 carried. That adds no input to the lock.

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
- A production bootstrap and relay pair for either line, once the Foundation documents one. The `holochain-bootstrap` module runs your own; it is tested over plain HTTP on a LAN, not yet with TLS.
