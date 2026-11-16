# ADR-023: A fleet layer for the admin plane and remote access

- **Status:** Accepted
- **Date:** 2026-11-07
- **Source:** AD6 of the architecture review of 2026-11-07 and 2026-11-15, summarised in [#98](https://github.com/Sensorica/nixos-holochain/issues/98)

## Context

[#72](https://github.com/Sensorica/nixos-holochain/pull/72) added the admin plane as a module, while the client half, the Tailscale client, lived in the lab's example.
The maintainer's homelab runs the same shape.

## Options considered

- **A fleet layer here, with the admin plane and remote access as generic modules, which the homelab consumes later.**
  One implementation of Headscale behind nginx, and any fleet, ours or an adopter's, gets remote access by enabling two modules.
- **Keep remote access in the example, and the admin plane as in #72.**
  No move, and the next fleet copies the remote-access file.
- **The homelab owns the shape and this repository imports it.**
  One source, but a public repository that depends on a private flake.

## Decision

The admin plane and remote access are generic modules in the fleet layer of this repository.

### Why

Remote access is what every fleet needs, and nothing in it is specific to one lab.

## Later record

- The admin plane is on `main` since [#72](https://github.com/Sensorica/nixos-holochain/pull/72), and the three-layer move ([#81](https://github.com/Sensorica/nixos-holochain/issues/81)) puts it in `modules/fleet/`. Promoting remote access out of the example is a separate unit.
