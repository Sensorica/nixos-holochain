# ADR-012: Nothing binary or secret in git

- **Status:** Amended (2026-08-28, SSH public keys are committed)
- **Date:** 2026-08-28
- **Source:** [#1](https://github.com/Sensorica/nixos-holochain/issues/1), issue description, section "Decisions (ADRs, continuing the numbering of the May design doc)"; amendment from the section "Amendments" of the same description

## Context

From the state of the repository recorded in #1 when the decision was taken (verified 2026-08-28):

> `happs/` is empty and `*.happ` is gitignored.

## Decision

> hApp bundles are fetched by hash (`pkgs.fetchurl`), never committed. SSH public keys stay under the gitignored `secrets/` with a committed `.example`.

## Consequences

The record states no consequences beyond the decision itself.

## Amendments

### 2026-08-28: SSH public keys are committed

From #1, section "Amendments", entry timed 01:45:

> **ADR-012 revised.** SSH public keys are not secrets: the example commits the operator public keys in `examples/sensorica-fleet/hosts/common.nix` (`users.users.sensorica.openssh.authorizedKeys.keys`, placeholder line for the operator to paste theirs). Reason: a flake only sees git-tracked files, so a gitignored `secrets/sensorica.pub` behind `builtins.pathExists` is never in the evaluated source and the fleet would deploy with no authorized key. Private keys, tokens and passphrases never enter git; that half stands. Detail: interim review comment on #2.

## Later record

- **Documentation images.** The slice 3 review ruled on 2026-08-28 ([#17 review](https://github.com/Sensorica/nixos-holochain/pull/17#issuecomment-5450968694)): "a PNG under `docs/images/` is documentation, not a hApp bundle or a secret; it is allowed. Keep such images small and dated, as this one is."
