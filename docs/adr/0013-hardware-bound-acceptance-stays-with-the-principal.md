# ADR-013: Hardware-bound acceptance stays with the principal

- **Status:** Accepted
- **Date:** 2026-08-28
- **Source:** [#1](https://github.com/Sensorica/nixos-holochain/issues/1), issue description, section "Decisions (ADRs, continuing the numbering of the May design doc)"; the list of hardware-bound issues is the section "Hardware-bound issues (not slices)" of the same description

"The principal" in the record is @Soushi888.

## Context

From #1:

> This epic is the design record for the `Workshop 2026` milestone. It is owned by the PM session of a PM/Builder binôme: the PM decides, decomposes and verifies; the Builder implements in stacked PRs.

## Decision

> Criteria that need a Holoport, the lab router or a participant are separate issues assigned to @Soushi888. The Builder closes only what a VM or CI can prove.

## Consequences

From #1, section "Hardware-bound issues (not slices)":

> Holoport vanilla NixOS boot test, dedicated router, `colmena apply` on the physical fleet, rollback demo on hardware, facilitator guide review with Tibi, preflight sent seven days out, and the workshop date itself. Each is its own issue, assigned to @Soushi888, labelled `hardware`.
