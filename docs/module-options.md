# Module Options Reference

This document is the canonical option reference for all nixos-holochain modules.

---

## holochain-edgenode

Core module: Holochain conductor + in-process lair keystore + hApp installer.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable the edgenode service |
| `package` | package | holonix `holochain` | Conductor binary |
| `hcPackage` | package | holonix `hc` | Holochain CLI used by the hApp installer. Validate name against pinned holonix commit. |
| `user` | string | `"holochain"` | System user the conductor runs as |
| `dataDir` | path | `/var/lib/holochain` | Persistent state: conductor DB, lair keystore, DHT data |
| `adminPort` | port | `4444` | Admin WebSocket port |
| `appPort` | port | `8888` | App WebSocket port |
| `allowedOrigins` | string | `"*"` | Allowed origins for admin WebSocket |
| `bootstrapUrl` | string | `https://bootstrap.holo.host` | DHT bootstrap server |
| `signalUrl` | string | `wss://signal.holo.host` | WebRTC signal server |
| `happs` | attrs | `{}` | hApps to install at first boot (keyed by app-id) |
| `happs.<name>.src` | path | — | Path to `.happ` bundle |
| `happs.<name>.networkSeed` | string\|null | null | Network seed for isolation |
| `happs.<name>.installed` | bool | true | Whether to install this hApp |
| `metricsExporter.enable` | bool | false | Enable Prometheus `node_exporter` for fleet observability |
| `metricsExporter.port` | port | `9100` | Port to expose node metrics on |
| `openFirewall` | bool | false | Open firewall for admin, app, and metrics ports |

### Services created

| Unit | Type | Condition |
|------|------|-----------|
| `holochain-conductor.service` | simple | always |
| `holochain-happ-installer.service` | oneshot | `happs != {}` |
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
