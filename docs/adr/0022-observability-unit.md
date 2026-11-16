# ADR-022: Observability is one unit

- **Status:** Accepted
- **Date:** 2026-11-07
- **Source:** AD5 of the architecture review of 2026-11-07 and 2026-11-15, summarised in [#98](https://github.com/Sensorica/nixos-holochain/issues/98); the choices were sent on the review board on 2026-11-07 at 16:29 (Montreal time)

## Context

The exporter was in `packages/`, its jq programs loose in `modules/`, the rules and the services in two modules, and the dashboards in two directories under `modules/`.

## Options considered

- **One `observability/` unit (exporter, jq programs, rules, dashboards and their tests), imported by the Grafana and rules modules.**
  One place for everything that produces a `holochain_*` series and draws it, with `tests/dashboards.nix` and `tests/metrics.nix` next to what they test.
- **Only move the jq programs and the dashboards into `modules/observability/`.**
  `modules/` is tidier, but the exporter stays a package elsewhere.

## Decision

The exporter, its jq programs, the recording rules, the dashboards and their tests become one `observability/` unit.

### Why

The exporter, its jq programs and the dashboards change together, since a new series touches all three, so they move together.

## Later record

- Not started as of 2026-11-15. The three-layer move ([#81](https://github.com/Sensorica/nixos-holochain/issues/81)) keeps the jq programs and dashboards under `modules/holochain/` until this unit.
