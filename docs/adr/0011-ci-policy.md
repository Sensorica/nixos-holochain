# ADR-011: CI policy

- **Status:** Accepted
- **Date:** 2026-08-28
- **Source:** [#1](https://github.com/Sensorica/nixos-holochain/issues/1), issue description, section "Decisions (ADRs, continuing the numbering of the May design doc)"

## Context

From the state of the repository recorded in #1 when the decision was taken (verified 2026-08-28):

> `nix flake check --no-build` fails: every `hosts/edgenode-0*/configuration.nix` imports a `hardware-configuration.nix` that is not in the tree. CI has failed on both pushes (runs 25826332473, 25826848922).

## Decision

> Eval jobs run on every push. VM tests are built in CI from slice 2 on (the workflow already enables KVM on `ubuntu-latest`). If the runner cannot build them, the PR says so with the run link and the PM re-derives the tests locally before any verdict.

## Consequences

The record states no consequences beyond the decision itself.
