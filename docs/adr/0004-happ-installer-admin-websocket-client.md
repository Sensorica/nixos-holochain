# ADR-004: hApp installer approach, two-step admin WebSocket client

- **Status:** Superseded by [ADR-006](0006-installer-on-hc-client-call.md)
- **Date:** 2026-05-13
- **Source:** Phase 1 architecture design of 2026-05-13, section 1 "Resolved Open Decisions (ADRs)". That document was never committed to this repository; [#1](https://github.com/Sensorica/nixos-holochain/issues/1) refers to it as "the May design doc" and continues its numbering. This file is its first copy in the repository.

## Context

The current scaffold uses `cfg.package` (the `holochain` conductor binary) to call `hc app install`; this is incorrect. The `holochain` binary is the conductor, not the CLI. The `hc` CLI is a separate package in holonix. Additionally, the installer service must poll for port readiness before connecting; the current scaffold starts immediately after the service unit activates, which races the conductor's startup.

## Decision

The installer service uses a wrapper script that calls the Holochain admin WebSocket API to install each hApp and attach the app interface. The wrapper prefers `hc app install --admin-ws-url` (if available in the pinned holonix version); if that subcommand is absent, it falls back to a minimal Node.js script using `@holochain/client`.

## Consequences

A `hcPackage` option is added to the module. The installer script gains an `ExecStartPre` readiness poll. The correct CLI invocation must be validated against the pinned holonix commit.

## Later record

- [ADR-006](0006-installer-on-hc-client-call.md) (2026-08-28) replaces this approach: the installer uses `hc client call`, and "The May design's Node.js fallback (§4.5) is dropped." #1 records that `hc app install` does not exist in the pinned holonix.
