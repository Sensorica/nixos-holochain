# ADR-018: Split `flake.nix` into flake-parts modules

- **Status:** Accepted
- **Date:** 2026-11-07
- **Source:** AD1 of the architecture review of 2026-11-07 and 2026-11-15, summarised in [#98](https://github.com/Sensorica/nixos-holochain/issues/98); the choices were sent on the review board on 2026-11-07 at 16:29 (Montreal time)

## Context

`flake.nix` had 3,088 lines in one file when the review was held, and grew to 3,212 before it was split.
Half of the VM tests were written inline in it and the other half lived in `tests/`.
Every pull request touched it, so every pull request conflicted on it, and reviewers read it as a single block.
flake-parts was already an input.

## Options considered

- **flake-parts modules under `nix/` (packages, modules, checks, templates, docs), and each test in `tests/<name>.nix`.**
  `flake.nix` keeps only the inputs and the imports, a test becomes a file to read and review, and pull requests stop fighting over one file.
  One mechanical pull request, verified by an identical `nix flake show` and a green list of checks.
- **Only move the inline tests to `tests/`, and keep the rest in `flake.nix`.**
  About a thousand lines fewer and a smaller change, but `flake.nix` still mixes packages, modules and docs.
- **Leave it.**
  No churn, and the file keeps growing with every module.

## Decision

`flake.nix` keeps the inputs and imports flake-parts modules under `nix/`, one per family of outputs, and every check has its own file under `tests/`.

### Why

The split is mechanical and verifiable, since the outputs are the same before and after, and it removes the file every pull request fought over.
flake-parts was already declared, so it adds no dependency.

## Consequences

The flake-parts part of the tooling track in [#57](https://github.com/Sensorica/nixos-holochain/issues/57) is done here.

## Later record

- [#77](https://github.com/Sensorica/nixos-holochain/pull/77) carried it out: `flake.nix` went from 3,212 lines to 51, with ten parts under `nix/` and one file per check under `tests/`. `nix flake show --json` stayed identical, and every derivation path stayed the same except one check that reads the whole source tree.
- The split left `nixosModules.default` importing a path that no longer existed, which no check imported; [#80](https://github.com/Sensorica/nixos-holochain/pull/80) fixed the import and added `checks.nixosModulesEval`, which evaluates every exported module.
