# ADR-029: v0.1.0 is the first community release

- **Status:** Accepted
- **Date:** 2026-11-15
- **Source:** AD12 of the architecture review of 2026-11-07 and 2026-11-15, summarised in [#98](https://github.com/Sensorica/nixos-holochain/issues/98)

## Context

The plan of 2026-09-27 made v0.1.0 the pilot's release: its exit criteria were five machines running from the tag, workshop participants joining, and the dashboard showing all five.
With the fleet and the workshop in a private repository, those criteria can no longer be checked in this repository, and the Holochain skill will point at the tag.

## Options considered

- **v0.1.0 is the first community release: generic modules, a neutral example, frozen option names and the publication guard. The lab's fleet becomes its first consumer, pinning the tag from its private repository.**
  The exit criteria are checked here: the `minimal` template initialises from the `v0.1.0` tag on a fresh NixOS, CI is green, and nothing names the lab.
  The pilot proves the release from outside, and the hardware and workshop issues move to the fleet's repository.
- **Keep v0.1.0 as the pilot's release, and make v0.2.0 the first community release.**
  The September plan holds as it is, but the first release carries a name and criteria that refer to a private repository.

## Decision

v0.1.0 is the first community release, with exit criteria provable in this public repository; the lab's fleet consumes the tag from outside.

### Why

The repository is meant to be shared, and the Holochain skill must point at a release a stranger can reproduce, so its exit criteria must be provable in the public repository.
The pilot stays the field proof, given from outside like any adopter's.

## Consequences

Soushi, 2026-11-15 20:09: the Holochain skill integrates at v1.0, not at v0.1.0, with a template initialised from the flake and a link to the option reference, together with [#46](https://github.com/Sensorica/nixos-holochain/issues/46).
