# ADR-030: The option prefix

- **Status:** Proposed
- **Date:** 2026-11-15
- **Source:** AD13 of the architecture review of 2026-11-07 and 2026-11-15, summarised in [#98](https://github.com/Sensorica/nixos-holochain/issues/98)

## Context

[ADR-025](0025-one-option-namespace.md) puts every option under one prefix; this record chooses it.
Today there are eight `services.holochain-*` prefixes and `services.admin-plane`, plus an option set specific to the lab.
nixpkgs has no `services.holochain` module today, but if it added one, two definitions of the same path would collide in any configuration that imports both.

## Options considered

- **`services.holochain.*`**
  The shortest and most natural name for an adopter.
  If nixpkgs ever adds `services.holochain`, it is renamed then, with aliases, as now.
- **`services.nixos-holochain.*`**
  No collision with nixpkgs is possible, at the price of a longer name that repeats the repository's name in every configuration.
- **`holochain.*` (outside `services`)**
  Short and free of collision with `services`, but outside the NixOS convention where a service lives under `services`.

## Decision

Proposed, not yet settled: `services.holochain.*`, the default until the interfaces review decides.

### Why

The collision is hypothetical and renaming later costs an alias, while the name adopters write every day is permanent.

## Consequences

The interfaces review settles the prefix and the names under it; this record moves to Accepted, or is amended, when it does.
