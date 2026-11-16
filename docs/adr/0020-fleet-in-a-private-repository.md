# ADR-020: The lab's fleet and workshop move to a private repository

- **Status:** Accepted
- **Date:** 2026-11-15
- **Source:** AD3 of the architecture review of 2026-11-07 and 2026-11-15, summarised in [#98](https://github.com/Sensorica/nixos-holochain/issues/98)
- **Supersedes:** [ADR-005](0005-fleet-becomes-an-example.md)

## Context

Reopened on 2026-11-15 at Soushi's request: `examples/` should hold only concrete, neutral examples, the repository should no longer be oriented to a workshop or wired to one lab, and the fleet and the workshop go to a repository of their own.
Measured that day: the repository is public, 70 of its 135 tracked files named the lab (case-insensitive, paths included), and the fleet published the lab's LAN address plan and its public host names.

## Options considered

- **A private repository for the fleet, the workshop, the event profile and the workshop's hApps; this repository keeps only the generic modules and a neutral example under `examples/`.**
  The public repository is ready to share, nothing in it names the lab, and the lab's topology leaves the public.
  The machines change checkout, and a change that touches a module and a host needs two pull requests.
- **A separate but public repository.**
  The same boundary, but the lab's address plan and public names stay visible to everyone.
- **Rename to `fleets/<lab>` in this repository (the choice of 2026-11-07).**
  One pull request per change, but the repository stays wired to the lab, which is no longer wanted.

## Decision

The fleet, the workshop, the event profile and the workshop's hApps move to a private repository.
This repository keeps the generic modules and a neutral example.

### Why

What is sensitive here is not a secret but the map of the lab, hence a private repository.
Two pull requests per cross-cutting change is a real cost during the pilot, but [ADR-019](0019-three-module-layers.md) makes the boundary clean, so the export becomes a move of directories.

## Consequences

What leaves: `examples/` for the lab's fleet, the event profile and its hApps, `workshop/`, `docs/workshop/`, the fleet's page in `docs/`, the workshop ISO and the desk host.
What stays: the `fleet` template (`node-01` to `node-05`, already neutral) and a new neutral example ([#41](https://github.com/Sensorica/nixos-holochain/issues/41)).
This decision supersedes [ADR-005](0005-fleet-becomes-an-example.md), which kept the fleet under `examples/`.

## Later record

- The private repository was created on 2026-11-15 ([#84](https://github.com/Sensorica/nixos-holochain/issues/84)); the move is [#85](https://github.com/Sensorica/nixos-holochain/issues/85).
