# ADR-002: hApp bundle strategy, files in repo under `happs/`

- **Status:** Superseded by [ADR-012](0012-nothing-binary-or-secret-in-git.md)
- **Date:** 2026-05-13
- **Source:** Phase 1 architecture design of 2026-05-13, section 1 "Resolved Open Decisions (ADRs)". That document was never committed to this repository; [#1](https://github.com/Sensorica/nixos-holochain/issues/1) refers to it as "the May design doc" and continues its numbering. This file is its first copy in the repository.

## Context

Workshop participants have the files present without network access during the event. The PRD explicitly states this.

## Decision

`.happ` bundle files live in `happs/` inside the repo and are referenced via `path` literals. They enter the Nix store at build time via the module's `src` option.

## Consequences

Repo size grows by the size of the `.happ` files (typically 1–20 MB each). Updating to a new hApp version requires a commit.

Phase 3 path: replace `src = ./happs/windtunnel.happ` with `src = pkgs.fetchurl { url = ...; sha256 = ...; }` as a flake input.

## Later record

- [ADR-012](0012-nothing-binary-or-secret-in-git.md) (2026-08-28) records the opposite rule: "hApp bundles are fetched by hash (`pkgs.fetchurl`), never committed." That is the rule on `main`; `happs/README.md` says bundles are not committed to this repository.
