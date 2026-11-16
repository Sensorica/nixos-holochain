# ADR-019: Three module layers, and the lab's pieces leave the generic flake

- **Status:** Accepted
- **Date:** 2026-11-07
- **Source:** AD2 of the architecture review of 2026-11-07 and 2026-11-15, summarised in [#98](https://github.com/Sensorica/nixos-holochain/issues/98); the choices were sent on the review board on 2026-11-07 at 16:29 (Montreal time)

## Context

The root flake promises modules only, and that a community user never evaluates the lab's hosts ([ADR-005](0005-fleet-becomes-an-example.md)).
Yet it exported the lab's event profile and its hApps, and the real fleet lived under `examples/`.

## Options considered

- **Three layers in the tree, `modules/holochain`, `modules/moss` and `modules/fleet`, and every piece specific to the lab moved into the fleet's flake.**
  The root flake exports generic modules only, and the profile and its hApps live where the only hosts that use them live.
  A homelab that imports the profile by path changes one path.
- **Keep one flat directory, prefix the lab's files, and keep them out of `default`.**
  The smallest change, but the generic flake still ships one client's profile.
- **Move the fleet to its own repository now.**
  The cleanest boundary, with its own lock and its own review, but the machines change checkout and every change that touches both needs two pull requests.

## Decision

The modules live in three layers, `modules/holochain`, `modules/moss` and `modules/fleet`, and the pieces specific to the lab leave the generic flake.

### Why

It restores the promise of ADR-005 without splitting repositories during a pilot.
A separate repository stays possible later, once the boundary is clean.

## Consequences

Where the lab's pieces go was decided again on 2026-11-15: a private repository, recorded in [ADR-020](0020-fleet-in-a-private-repository.md).

## Later record

- The layer move is [#81](https://github.com/Sensorica/nixos-holochain/issues/81); the lab's event profile and hApps stay at the top of `modules/` until the fleet export, [#85](https://github.com/Sensorica/nixos-holochain/issues/85).
