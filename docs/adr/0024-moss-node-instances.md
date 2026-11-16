# ADR-024: Several Moss nodes on one machine

- **Status:** Accepted
- **Date:** 2026-11-07
- **Source:** AD7 of the architecture review of 2026-11-07 and 2026-11-15, summarised in [#98](https://github.com/Sensorica/nixos-holochain/issues/98)

## Context

The Moss node module fixes the unit and the user to `moss-node`, so a node on the 0.15 line and a node on the 0.16 line need two machines.

## Options considered

- **Instances, `instances.<name>` under the Moss node module, each with its own unit, user, data directory and line.**
  One machine can carry two groups, at the cost of an option change with a migration of the existing single node.
- **Keep one node per machine.**
  No change, and the pilot takes a second machine.

## Decision

The Moss node module takes named instances, each with its own unit, user, data directory and line.

### Why

The fleet has five machines and two groups today, more later, and instances are the NixOS idiom for exactly that.

## Consequences

The option change comes with a migration of the existing single node; its names follow [ADR-025](0025-one-option-namespace.md).

## Later record

- Not started as of 2026-11-15.
