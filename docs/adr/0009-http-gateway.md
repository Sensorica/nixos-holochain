# ADR-009: HTTP gateway

- **Status:** Amended (2026-08-28, built from source per line)
- **Date:** 2026-08-28
- **Source:** [#1](https://github.com/Sensorica/nixos-holochain/issues/1), issue description, section "Decisions (ADRs, continuing the numbering of the May design doc)"; amendment from [#15](https://github.com/Sensorica/nixos-holochain/issues/15), issue description, section "6. Decisions (ADR amendments, effective now)", copied into #1 under "Amendments from the research record"

The title in #1 is "HTTP gateway is `hc http-gw`"; the amendment replaced that choice, so this file keeps the subject as its title.

## Context

From the state of the repository recorded in #1 when the decision was taken (verified 2026-08-28):

> The same `hc` build ships an `hc http-gw` extension (needs `HC_GW_ADMIN_WS_URL`).

> `holochain-windtunnel`, `holochain-http-gateway` and `pai` modules are `warnings = [...]` placeholders.

## Decision

> The gateway module wraps the extension shipped with holonix's `hc`, configured from the module's `adminPort` and `listenPort`.

## Consequences

The record states no consequences beyond the decision itself.

## Amendments

### 2026-08-28: the gateway is built from source per line

From #15, section 6:

> `holochain_http_gateway` v0.4.x for 0.7, v0.3.x for 0.6, packaged with `rustPlatform.buildRustPackage` from the tagged source (Cargo.lock present), never the `hc http-gw` bundled in holonix's `hc`. Module options mirror spec.md (`allowedAppIds`, `allowedFns` per app, `payloadLimitBytes`, `maxAppConnections`, `zomeCallTimeoutMs`, `address`, `port`); default exposes nothing. Reference implementation: Holo-Host/holo-host `nix/modules/nixos/hc-http-gw`.

Its context, from #15 section 2: hc-http-gw publishes one release line per Holochain line (0.6.x → 0.3.x, 0.7.x → 0.4.x), and "The `hc http-gw` bundled in holonix `main-0.7`'s `hc` reports crate 0.3.1: wrong line for 0.7, do not use it."

Consequence recorded in #15, section 7, for slice 4 ([#5](https://github.com/Sensorica/nixos-holochain/issues/5)): "gateway from source per line with the spec.md options".

## Later record

- [docs/architecture.md § Not the bundled `hc http-gw`](../architecture.md#not-the-bundled-hc-http-gw) describes the build on `main` and the release pinned for each line.
