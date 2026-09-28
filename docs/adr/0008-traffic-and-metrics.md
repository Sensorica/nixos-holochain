# ADR-008: Traffic and metrics

- **Status:** Amended (2026-08-28, the runner is compute donation)
- **Date:** 2026-08-28
- **Source:** [#1](https://github.com/Sensorica/nixos-holochain/issues/1), issue description, section "Decisions (ADRs, continuing the numbering of the May design doc)"; amendment from [#15](https://github.com/Sensorica/nixos-holochain/issues/15), issue description, section "6. Decisions (ADR amendments, effective now)", copied into #1 under "Amendments from the research record"

## Context

From the state of the repository recorded in #1 when the decision was taken (verified 2026-08-28):

> `holochain-windtunnel`, `holochain-http-gateway` and `pai` modules are `warnings = [...]` placeholders.

#1 also left open, with an owner, "Whether the Wind Tunnel runner is the workshop's traffic source or Moss on laptops: PM, after slice 3 shows what the dashboard looks like."

## Decision

> The Wind Tunnel module runs the Foundation's `ghcr.io/holochain/wind-tunnel-runner` image through `virtualisation.oci-containers` (host network, privileged, `nomad-client-<hostname>` naming as in Sensorica's April plan). Conductor-level metrics come from our own systemd timer that writes `hc client call dump-network-stats` output to a node_exporter textfile. A native Wind Tunnel package is out of scope.

## Consequences

The record states no consequences beyond the decision itself.

## Amendments

### 2026-08-28: the Wind Tunnel runner is compute donation, not the dashboard's traffic

From #15, section 6:

> The `ghcr.io/holochain/wind-tunnel-runner` container runs its own conductor and reports to the Foundation's Nomad/InfluxDB, and its README calls it internal-use. The module keeps it as an opt-in (`services.holochain-windtunnel.enable`, default off, documented as "donate this machine to the Foundation's test cluster") and the Grafana dashboard's traffic comes from our conductor stats exporter (`hc client call dump-network-stats` → textfile → node_exporter) plus real participant activity on the fleet's hApps. No local Wind Tunnel scenario runs in scope (the tagged scenarios target 0.6.3 and the nightly 0.7 ones are unreleased).

Consequence recorded in #15, section 7, for slice 3 ([#4](https://github.com/Sensorica/nixos-holochain/issues/4)): "Wind Tunnel runner opt-in and off by default; the dashboard's `holochain_*` gauge becomes the primary criterion."
