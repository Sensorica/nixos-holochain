# ADR-001: Lair keystore, in-process for Phase 1

- **Status:** Accepted
- **Date:** 2026-05-13
- **Source:** Phase 1 architecture design of 2026-05-13, section 1 "Resolved Open Decisions (ADRs)". That document was never committed to this repository; [#1](https://github.com/Sensorica/nixos-holochain/issues/1) refers to it as "the May design doc" and continues its numbering. This file is its first copy in the repository.

## Context

In-proc eliminates an ordering dependency (no need for lair to be ready before conductor). The workshop context has no key persistence requirements beyond a single session. The PRD explicitly recommends this.

## Decision

Keep `keystore.type: lair_server_in_proc` in conductor config. A separate `lair-keystore.service` is deferred to Phase 4.

## Consequences

Keys are derived from the in-proc lair on every start. State persists in `cfg.dataDir` so keys survive restarts. Production multi-key scenarios are out of scope.

Phase 4 path: add `lair-keystore.service` unit, change config to `type: lair_server_tcp` with a socket path.

## Later record

- [ADR-016](0016-passphrase-and-readiness.md) (2026-08-28) records how the lair passphrase is generated and fed to the conductor. The keystore itself is still in-process on `main`: `modules/holochain-edgenode.nix` renders `type: lair_server_in_proc`.
