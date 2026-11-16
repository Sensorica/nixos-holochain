# ADR-026: The flake split first, the open branches rebased on it

- **Status:** Accepted
- **Date:** 2026-11-15
- **Source:** AD9 of the architecture review of 2026-11-07 and 2026-11-15, summarised in [#98](https://github.com/Sensorica/nixos-holochain/issues/98)

## Context

The refactor had not started.
Two open pieces of work touched the files it moves: the Grafana cookie and dynamic DNS branch (`admin-plane.nix`, no pull request yet) and the DNS drift pull request (`holochain-rules.nix`, draft).
The flake split rewrites `flake.nix` end to end, so any branch open during it must be rebased on a split file.

## Options considered

- **Land the two remote-access branches first, then split on a quiet `main`.**
  No branch to rebase across the split, and remote access advances first; the split waits a few more days.
- **Split now, and rebase the two branches afterwards.**
  The refactor starts today, at the cost of two rebases across a split `flake.nix`; remote access waits.
- **Keep the refactor for after the lab's event.**
  The lab and the event come first, and `flake.nix` keeps growing until then.

## Decision

Split `flake.nix` now ([ADR-018](0018-split-flake-nix.md)), and rebase the two open branches on it.

### Why

Soushi chose to start the refactor at once rather than wait for a quiet `main`.

## Later record

- The DNS drift pull request merged first, then the split ([#77](https://github.com/Sensorica/nixos-holochain/pull/77)), and the Grafana branch was rebased on the split before it merged.
