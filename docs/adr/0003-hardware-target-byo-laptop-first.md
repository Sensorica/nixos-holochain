# ADR-003: Hardware target, BYO laptop as safe fallback; Holoport validation a pre-Phase-2 gate

- **Status:** Accepted
- **Date:** 2026-05-13
- **Source:** Phase 1 architecture design of 2026-05-13, section 1 "Resolved Open Decisions (ADRs)". That document was never committed to this repository; [#1](https://github.com/Sensorica/nixos-holochain/issues/1) refers to it as "the May design doc" and continues its numbering. This file is its first copy in the repository.

## Context

Phase 1's sole purpose is module correctness. Hardware compatibility is a deployment concern. Running CI in a NixOS VM already proves the module works; physical hardware is a Phase 2 concern.

## Decision

Phase 1 develops and validates the module on a BYO laptop or VM. Whether Holoports accept vanilla NixOS is a gate for Phase 2 hardware selection, not a Phase 1 blocker.

## Consequences

Action: file a GitHub issue to track Holoport NixOS compatibility testing as a Phase 2 gate.

## Later record

- The gate is tracked in [#8](https://github.com/Sensorica/nixos-holochain/issues/8), "Hardware: one Holoport boots vanilla NixOS from the workshop ISO (ADR-003 gate)".
- [ADR-013](0013-hardware-bound-acceptance-stays-with-the-principal.md) and [ADR-017](0017-holoport-legacy-bios-target.md) (2026-08-28) record who accepts hardware-bound criteria and what the Holoport is as a target.
