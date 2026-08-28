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
| `metricsExporter.enable` | bool | `false` | Enable Prometheus `node_exporter` for fleet observability |
| `metricsExporter.port` | port | `9100` | Port to expose node metrics on |
| `openFirewall` | bool | `false` | Open firewall for admin, app, and metrics ports |

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

---

## holochain-grafana

Prometheus + Grafana observability stack. Enable on the designated monitor node;
peer nodes expose metrics via `services.holochain-edgenode.metricsExporter.enable = true`.

Access dashboard at `http://<monitor-host>:3000` (default credentials: admin / workshop2026).

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable Prometheus + Grafana stack |
| `grafanaPort` | port | `3000` | Grafana HTTP port |
| `prometheusPort` | port | `9090` | Prometheus port |
| `scrapeTargets` | list of string | `[]` | `node_exporter` targets across the fleet (`"host:port"`) |
| `windtunnelTargets` | list of string | `[]` | Wind Tunnel metrics targets — leave empty until Wind Tunnel binary is available |
| `openFirewall` | bool | false | Open firewall for Grafana, Prometheus, and node_exporter ports |

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

# edgenode-02..05 (peer role)
services.holochain-edgenode.metricsExporter.enable = true;
```

### Services created

| Unit | Type |
|------|------|
| `grafana.service` | simple |
| `prometheus.service` | simple |
| `prometheus-node_exporter.service` | simple |

---

## holochain-windtunnel

Placeholder — Wind Tunnel scenario runner. Implementation pending Wind Tunnel stable release.
See module file for current status and `metricsPort` option.

## holochain-http-gateway

Placeholder — HTTP gateway in front of the conductor.
Gateway binary not yet selected. See module file for current status.

## pai

Placeholder — PAI per-machine. See module file for current status.
