# Architecture decision records

These are the design decisions behind `nixos-holochain`, one file per ADR. ADR-005 to ADR-017 were first recorded in the descriptions of issues [#1](https://github.com/Sensorica/nixos-holochain/issues/1) (the design record for the 2026 workshop milestone) and [#15](https://github.com/Sensorica/nixos-holochain/issues/15) (the research record of 2026-08-28). ADR-001 to ADR-004 belong to the Phase 1 architecture design of 2026-05-13, which #1 calls "the May design doc" and whose numbering it continues; that document is not in this repository, and its ADRs are not published here. Moving them here ([#39](https://github.com/Sensorica/nixos-holochain/issues/39)) keeps the record next to the code it explains.

| ADR | Title | Status | Date | Source |
|---|---|---|---|---|
| 001 | Not published: recorded in the May 2026 design, which is not in this repository | | 2026-05-13 | May design |
| 002 | Not published: recorded in the May 2026 design, which is not in this repository | | 2026-05-13 | May design |
| 003 | Not published: recorded in the May 2026 design, which is not in this repository | | 2026-05-13 | May design |
| 004 | Not published: recorded in the May 2026 design, which is not in this repository | | 2026-05-13 | May design |
| [005](0005-fleet-becomes-an-example.md) | Fleet becomes an example | Accepted | 2026-08-28 | #1 |
| [006](0006-installer-on-hc-client-call.md) | Installer on `hc client call` | Accepted | 2026-08-28 | #1 |
| [007](0007-toolchain-pins.md) | Toolchain pins | Amended 2026-08-28 | 2026-08-28 | #1, #15 |
| [008](0008-traffic-and-metrics.md) | Traffic and metrics | Amended 2026-08-28 | 2026-08-28 | #1, #15 |
| [009](0009-http-gateway.md) | HTTP gateway | Amended 2026-08-28 | 2026-08-28 | #1, #15 |
| [010](0010-stack-shape.md) | Stack shape | Accepted | 2026-08-28 | #1 |
| [011](0011-ci-policy.md) | CI policy | Accepted | 2026-08-28 | #1 |
| [012](0012-nothing-binary-or-secret-in-git.md) | Nothing binary or secret in git | Amended 2026-08-28 | 2026-08-28 | #1 |
| [013](0013-hardware-bound-acceptance-stays-with-the-principal.md) | Hardware-bound acceptance stays with the principal | Accepted | 2026-08-28 | #1 |
| [014](0014-verification-modality.md) | Verification modality | Accepted | 2026-08-28 | #1 |
| [015](0015-sensorica-fleet-pins-0-6-3.md) | The Sensorica fleet pins 0.6.3 for the September workshop | Accepted | 2026-08-28 | #15 |
| [016](0016-passphrase-and-readiness.md) | Passphrase and readiness follow Holo's module | Accepted | 2026-08-28 | #15 |
| [017](0017-holoport-legacy-bios-target.md) | HoloPort is a legacy-BIOS x86_64 target | Accepted | 2026-08-28 | #15 |

Every ADR number that the repository, #1 or #15 refers to from 005 to 017 has its text here. ADR-001 to ADR-004 are cited only by number: in #1, which continues their numbering, and in the title of [#8](https://github.com/Sensorica/nixos-holochain/issues/8) (ADR-003).

## How to read a file

Each file has a Status, a Date, a Source, then Context, Decision and Consequences. Text in a quote block is copied from #1 or #15 as written, and the context is taken from the same issue. Where the source gives no context or consequence for a decision, the file says so rather than supplying one.

- **Amendments** are recorded inside the ADR they change, with their date, below the original decision. The original text stays.
- **Later record** lists what happened after the decision where it bears on it: a ruling in a PR review, or a place where `main` no longer matches the recorded text and the record was not amended. Each entry links its evidence. These entries are observations, not new decisions.

In #1 and #15, "the principal" is @Soushi888, "PM" and "Builder" are the two roles of the paired sessions that built the 2026 stack, and a "slice" is one PR of that stack.

## What stays in the issues

Issue #1 also records working rules for the 2026 PM/Builder sessions (draft PRs, where a bug found in a slice gets fixed, commit cadence) and the open questions of that milestone. They are process for one milestone, not numbered decisions, so they stay in the issue. Issue #15 is also a research record of the Holochain ecosystem as of 2026-08-28; only its decisions are copied here.
