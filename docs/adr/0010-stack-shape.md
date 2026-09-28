# ADR-010: Stack shape

- **Status:** Accepted
- **Date:** 2026-08-28
- **Source:** [#1](https://github.com/Sensorica/nixos-holochain/issues/1), issue description, section "Decisions (ADRs, continuing the numbering of the May design doc)"

## Context

From #1:

> This epic is the design record for the `Workshop 2026` milestone. It is owned by the PM session of a PM/Builder binôme: the PM decides, decomposes and verifies; the Builder implements in stacked PRs.

## Decision

> Trunk is `main`. Five slices, each a PR based on the previous slice's branch: `slice/1-flake-evaluates` → `slice/2-conductor-happ` → `slice/3-observability` → `slice/4-community-shape` → `slice/5-workshop-kit`. The principal squash-merges in order; after each merge the next slice is rebased onto `main` and its PR base edited.

## Consequences

The record states no consequences beyond the decision itself.

## Related record in #1

#1 records the slice order, the gate and an amendment to the gate in their own sections, not as part of ADR-010. They are copied here because they describe the same stack.

The slice order, from #1, section "Slice order (a real dependency chain)":

| Slice | Branch | Base | Closes |
|---|---|---|---|
| 1 Flake evaluates, fleet as example, toolchain on 0.7, CI green | `slice/1-flake-evaluates` | `main` | evaluation, layout, pins, CI |
| 2 Conductor and hApp at boot, VM-tested | `slice/2-conductor-happ` | slice 1 | the module actually works |
| 3 Observability: fleet traffic on Grafana | `slice/3-observability` | slice 2 | the workshop's high point |
| 4 Community shape: templates, gateway, truthful docs | `slice/4-community-shape` | slice 3 | reuse by strangers |
| 5 Workshop kit: ISO, fleet runbook, materials, two-node fleet test | `slice/5-workshop-kit` | slice 4 | the day itself |

> Slice 2 depends on 1 (the flake must evaluate before a VM test can build). 3 depends on 2 (metrics need a running conductor). 4 depends on 3 (README truth needs the modules real). 5 depends on 4 (materials reference the final layout and template).

The gate, from #1, section "Gate":

> The child slice's PR is published only after the parent's PR carries a `PM review: APPROVE` comment and the child branch contains the parent's current head (`git merge-base --is-ancestor <parent> HEAD`). Local work ahead of the verdict is fine; publishing it is not.

The amendment to the gate, from #1, section "Amendments", entry timed 01:58 (the entry names the gate, not ADR-010):

> Verdicts are PR comments, not GitHub review approvals: both sessions act under the principal's account and GitHub refuses "approve your own pull request". The gate reads the `PM review: APPROVE` comment; the principal's merge is the release.

## Later record

- The stack landed as seven slices, not five: [#13](https://github.com/Sensorica/nixos-holochain/pull/13), [#16](https://github.com/Sensorica/nixos-holochain/pull/16), [#17](https://github.com/Sensorica/nixos-holochain/pull/17), [#18](https://github.com/Sensorica/nixos-holochain/pull/18), [#19](https://github.com/Sensorica/nixos-holochain/pull/19), then `slice/6-nixos-26.05` ([#20](https://github.com/Sensorica/nixos-holochain/pull/20)) and `slice/7-review-hardening` ([#21](https://github.com/Sensorica/nixos-holochain/pull/21)). All seven were merged on 2026-09-26 with merge commits (`git log --merges` on `main`), not squash-merged. #1 was not amended.
