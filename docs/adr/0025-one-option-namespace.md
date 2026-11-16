# ADR-025: One option namespace before v0.1

- **Status:** Accepted
- **Date:** 2026-11-07
- **Source:** AD8 of the architecture review of 2026-11-07 and 2026-11-15, summarised in [#98](https://github.com/Sensorica/nixos-holochain/issues/98); the choices were sent on the review board on 2026-11-07 at 16:29 (Montreal time)

## Context

`services.holochain-edgenode`, `services.holochain-grafana`, `services.holochain-moss-node`, `services.admin-plane` and an option set specific to the lab coexisted.
The option stability policy is still open ([#45](https://github.com/Sensorica/nixos-holochain/issues/45)).

## Options considered

- **One namespace, `services.holochain.<part>`, with `mkRenamedOptionModule` aliases for one release.**
  One prefix to learn, the aliases keep every host evaluating, and it is done once, before v0.1 makes the names a promise.
- **Keep today's names.**
  No churn, and adopters learn five prefixes.

## Decision

All options move under one namespace, with rename aliases for one release.

### Why

Renaming costs little now and becomes a breaking change after v0.1.
The aliases make the operation safe for the machines already deployed.

## Consequences

Soushi's note of 2026-11-07: think the naming through before crystallising it and making breaking API changes.
The naming is therefore decided on an interfaces board before this decision is implemented; the prefix itself is [ADR-030](0030-option-prefix.md).
