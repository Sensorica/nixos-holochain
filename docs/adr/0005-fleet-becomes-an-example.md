# ADR-005: Fleet becomes an example

- **Status:** Accepted
- **Date:** 2026-08-28
- **Source:** [#1](https://github.com/Sensorica/nixos-holochain/issues/1), issue description, section "Decisions (ADRs, continuing the numbering of the May design doc)"

## Context

From the state of the repository recorded in #1 when the decision was taken (verified 2026-08-28):

> `nix flake check --no-build` fails: every `hosts/edgenode-0*/configuration.nix` imports a `hardware-configuration.nix` that is not in the tree. CI has failed on both pushes (runs 25826332473, 25826848922).

> `colmena` output declares nodes without importing any module.

## Decision

> The Sensorica fleet (5 hosts + workshop ISO + colmena hive) moves to `examples/sensorica-fleet/` with its own `flake.nix` that takes the root flake as input. The root flake keeps modules, templates and VM checks only, so a community user never evaluates Sensorica hosts. Committed `hardware-configuration.nix` stubs make each host evaluate; the example README documents replacing them with `nixos-generate-config` output.

## Consequences

The record states no consequences beyond the decision itself.
