# Module Options Reference

This document is the canonical option reference for all nixos-holochain modules.

---

## holochain-edgenode

Core module: Holochain conductor + in-process lair keystore + idempotent hApp installer.

Supports the 0.6 and 0.7 lines from one option set. Everything version-dependent is derived from `package.version`, so setting `package` and `hcPackage` to the 0.6 toolchain is the whole of what switching lines requires.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the edgenode service |
| `package` | package | holonix `main-0.7` `holochain` (0.7.0) | Conductor binary. Its version selects the config schema the module renders |
| `hcPackage` | package | holonix `main-0.7` `hc` (0.7.0) | CLI used by the hApp installer. Keep it on the same line as `package` |
| `user` | string | `"holochain"` | System user the conductor runs as |
| `dataDir` | path | `/var/lib/holochain` | Persistent state: conductor DB, lair keystore, passphrase. Kept short on purpose (`SUN_LEN`) |
| `passphraseFileName` | string | `"lair-passphrase"` | Passphrase file inside `dataDir`, generated 0600 on first boot |
| `adminPort` | port | `4444` | Admin WebSocket port (bound to localhost) |
| `appPort` | port | `8888` | App WebSocket port the installer attaches |
| `allowedOrigins` | string | `"*"` | Allowed origins for the admin and app WebSockets |
| `bootstrapUrl` | string\|null | `null` | Bootstrap server. `null` selects `https://dev-test-bootstrap2.holochain.org` below 0.7, the same URL with a trailing slash from 0.7 |
| `signalUrl` | string\|null | `null` | WebRTC signal server, **0.6 line only**. `null` selects `wss://dev-test-bootstrap2.holochain.org`. Ignored with a warning from 0.7, where the key was removed from the schema |
| `relayUrl` | string\|null | `null` | Iroh relay, required on both lines. `null` selects `https://use1-1.relay.n0.iroh-canary.iroh.link./` |
| `installerTimeout` | int | `300` | Seconds the installer waits for the admin interface to answer |
| `useSystemdNotify` | bool | `true` | Run the conductor as `Type = "notify"`; false falls back to `Type = "simple"` |
| `happs` | attrs | `{}` | hApps to install and keep enabled (keyed by installed app id) |
| `happs.<name>.src` | path | — | Path to the `.happ` bundle. Fetch by hash; never commit one |
| `happs.<name>.installed` | bool | `true` | Whether to install and enable this hApp |
| `happs.<name>.networkSeed` | string\|null | `null` | Network seed override for every DNA in the app |
| `metricsExporter.enable` | bool | `false` | Enable Prometheus `node_exporter` for fleet observability, with the textfile collector on |
| `metricsExporter.port` | port | `9100` | Port to expose node metrics on |
| `metricsExporter.textfileDirectory` | path | `/var/lib/prometheus-node-exporter-text-files` | Directory the textfile collector reads; created 0755 owned by `user` |
| `conductorMetrics.enable` | bool | `false` | Export the conductor's own network stats as `holochain_*` series. Requires `metricsExporter.enable` |
| `conductorMetrics.interval` | string | `"30s"` | systemd time span between textfile writes |
| `openFirewall` | bool | `false` | Open firewall for admin, app, and metrics ports |

### Conductor metrics

`conductorMetrics.enable` is the fleet dashboard's Holochain data source, and the only one: the Wind Tunnel runner is not a data source (see below). A systemd timer calls `dump-network-stats` on the admin interface every `interval`, turns the reply into Prometheus text with `jq`, and writes it into `metricsExporter.textfileDirectory`, from which node_exporter serves it on `/metrics`.

The reply is Kitsune2's `TransportStats`, byte-identical on both lines. Verified against the pinned 0.7.0 and 0.6.3 binaries:

```json
{"transport_stats":{"backend":"iroh","peer_urls":["https://use1-1.relay.n0.iroh-canary.iroh.link.:443/57b3f7ba..."],"connections":[]},"blocked_message_counts":{}}
```

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

A down or restarting conductor reports `holochain_conductor_up 0` rather than dropping the series, so a dead node shows on the dashboard instead of vanishing from it. The byte and message counters cover the connections the conductor holds *right now*: a peer that disconnects takes its totals with it, so they can go down. Treat them as throughput of live links, which is what `rate()` over them means, and not as lifetime totals.

The three URL options default to `null` rather than to a literal so that one default can serve both lines. `null` means "whatever the configured Holochain version uses for itself"; the resolved values are in the table above and in `docs/architecture.md`. None of them is a production endpoint.

### Running the 0.6 line

```nix
services.holochain-edgenode = {
  enable = true;
  package = inputs.holonix-0_6.packages.${pkgs.system}.holochain;
  hcPackage = inputs.holonix-0_6.packages.${pkgs.system}.hc;
};
```

Or, against this flake's own outputs, `nixos-holochain.packages.${system}.holochain-0_6` and `hc-0_6`.

### Services created

| Unit | Type | Condition |
|------|------|-----------|
| `holochain-conductor.service` | notify (simple when `useSystemdNotify = false`) | always |
| `holochain-happ-installer.service` | oneshot, `RemainAfterExit`, runs every boot | `happs != {}` |
| `prometheus-node_exporter.service` | simple | `metricsExporter.enable` |
| `holochain-conductor-metrics.service` | oneshot, driven by the timer | `conductorMetrics.enable` |
| `holochain-conductor-metrics.timer` | `OnBootSec` / `OnUnitActiveSec` = `interval` | `conductorMetrics.enable` |

---

## holochain-grafana

Prometheus + Grafana observability stack. Enable on the designated monitor node;
peer nodes expose metrics via `services.holochain-edgenode.metricsExporter.enable = true`
and `services.holochain-edgenode.conductorMetrics.enable = true`.

Access the dashboard at `http://<monitor-host>:3000` (default credentials: admin / workshop2026).

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Prometheus + Grafana stack |
| `grafanaPort` | port | `3000` | Grafana HTTP port |
| `prometheusPort` | port | `9090` | Prometheus port |
| `scrapeTargets` | list of string | `[]` | `node_exporter` targets across the fleet (`"host:port"`) |
| `scrapeInterval` | string | `"15s"` | How often Prometheus scrapes. Below its own one-minute default, which draws a short window nearly flat |
| `adminUser` | string | `"admin"` | Grafana administrator account |
| `adminPassword` | string | `"workshop2026"` | Grafana administrator password. A lab convenience, not a secret: it ends up world-readable in the Nix store |
| `dashboards` | path | `./dashboards` | Directory of dashboard JSON files to provision |
| `openFirewall` | bool | `false` | Open firewall for Grafana, Prometheus, and node_exporter ports |

`windtunnelTargets` was removed in slice 3. The Wind Tunnel runner image exposes no Prometheus endpoint: its config declares no ports, its entrypoint is a Nomad agent, and neither its README nor its repository mentions Prometheus or metrics. A scrape target option for it would have pointed at nothing.

### Provisioning

The module provisions both halves, so a fresh monitor node comes up with a working dashboard and nothing to click:

- a Prometheus data source with uid `holochain-prometheus`, pointed at `127.0.0.1:<prometheusPort>`. The shipped dashboard refers to it by uid, so renaming it in the UI cannot break it.
- every JSON file in `dashboards`, re-read every 30 seconds. `allowUiUpdates` is off: the files come from the Nix store, so edits made in the UI would be discarded by the next rebuild without saying so.

`modules/dashboards/holochain-fleet.json` (uid `holochain-fleet`, title "Holochain Fleet") has six panels: conductors up, conductor peers, conductor network throughput, CPU busy, memory used, and host network throughput. The first three come from the edgenode module's `conductorMetrics`; the last three from node_exporter.

A conductor with no hApp installed joins no DHT, so its connection and byte counts sit at zero while `holochain_conductor_up` and `holochain_conductor_peer_urls` are already non-zero. That is the correct reading of a bare node, not a broken panel.

### Example: 5-node fleet

```nix
# edgenode-01 (monitor role)
services.holochain-grafana = {
  enable        = true;
  openFirewall  = true;
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

### Services created

| Unit | Type |
|------|------|
| `grafana.service` | simple |
| `prometheus.service` | simple |
| `prometheus-node_exporter.service` | simple |

---

## holochain-windtunnel

Runs the Holochain Foundation's Wind Tunnel runner image as an OCI container.

**This module is not a source of dashboard data, and enabling it donates the machine.** The image's entrypoint synchronises the clock and then execs `nomad agent`; the baked config sets `client.servers = ["nomad-server-01.holochain.org"]`. So the machine joins the Foundation's Nomad cluster as a client, and the Foundation schedules Wind Tunnel scenarios — each with its own conductor — onto it. The runner's README calls these machines "designed to be for internal use only" and warns that the image "requires extensive permissions on the host machine that are effectively root access" and "should only be run on a dedicated machine". `enable` therefore defaults to `false`, and the example fleet sets it to `false` in writing.

The fleet's `holochain_*` series come from `services.holochain-edgenode.conductorMetrics`, which needs none of this.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Donate this machine to the Foundation's Wind Tunnel test network |
| `backend` | `"podman"` \| `"docker"` | `"podman"` | OCI backend. Podman needs no daemon; the README documents Docker and the image is indifferent |
| `image` | string | `ghcr.io/holochain/wind-tunnel-runner@sha256:650c9180...330fa2` | Runner image, pinned by digest |
| `hostname` | string | `"nomad-client-${networking.hostName}"` | Name the container reports to Nomad and Tailscale |
| `autoStart` | bool | `true` | Start the container at boot |
| `extraOptions` | list of string | `["--net=host" "--privileged" "--cgroupns=host"]` | Flags the README requires; removing any of them stops the runner working |

The image publishes only the moving tags `latest`, `latest-amd64` and `latest-arm64`, so the default pins the multi-architecture index digest that `latest` resolved to on 2026-08-28. Re-pin with `skopeo inspect docker://ghcr.io/holochain/wind-tunnel-runner:latest`.

### Services created

| Unit | Type | Condition |
|------|------|-----------|
| `podman-wind-tunnel-runner.service` | simple, from `virtualisation.oci-containers` | `enable` |

## holochain-http-gateway

Placeholder — HTTP gateway in front of the conductor.
Gateway binary not yet selected. See module file for current status.

## pai

Placeholder — PAI per-machine. See module file for current status.
