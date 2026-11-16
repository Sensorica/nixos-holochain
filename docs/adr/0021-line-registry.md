# ADR-021: A registry of Holochain and Moss lines

- **Status:** Accepted
- **Date:** 2026-11-07
- **Source:** AD4 of the architecture review of 2026-11-07 and 2026-11-15, summarised in [#98](https://github.com/Sensorica/nixos-holochain/issues/98)

## Context

Five builds were pinned across packages and inputs, and each module took its packages one by one.
The Moss pilot needed a new wdocker file, a bootstrap file and an assertion to check that the right pair had been chosen.

## Options considered

- **A registry of lines: one record per line naming all of its packages, chosen by name (`line = "0.7"`).**
  A new line fits in one record, the modules check that the pieces of a line belong together, and the dashboards can label by line.
  One module option changes, with a rename alias.
- **Keep the per-package options, and document which ones go together.**
  No option changes, but mismatched pairs stay possible and are found at runtime.

## Decision

Hosts choose a line by name from a registry of lines, each record naming every package of that line.

### Why

Which packages go together is a fact about the line, not about the host, so it belongs in one place.
The pilot's version-mismatch failure is exactly what a registry rules out at evaluation time.

## Consequences

One module option changes, with a rename alias; its name is settled together with the option namespace ([ADR-025](0025-one-option-namespace.md)).

## Later record

- Not started as of 2026-11-15.
