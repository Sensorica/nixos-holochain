# ADR-006: Installer on `hc client call`

- **Status:** Accepted
- **Date:** 2026-08-28
- **Source:** [#1](https://github.com/Sensorica/nixos-holochain/issues/1), issue description, section "Decisions (ADRs, continuing the numbering of the May design doc)"

## Context

From the state of the repository recorded in #1 when the decision was taken (verified 2026-08-28):

> The hApp installer in `modules/holochain-edgenode.nix` calls `hc app install`, `hc app enable` and `hc app attach-interface`. None exist. In the pinned holonix (rev `d49ebd5e7a`, Holochain `0.7.0-dev.24`), `hc app` has only `init | pack | unpack | schema`. The admin calls live under `hc client call --port <admin-port> install-app | enable-app | add-app-ws | list-apps | dump-network-stats | dump-network-metrics`.

## Decision

> The hApp installer service uses `hc client call --port ${adminPort} install-app`, `enable-app`, `add-app-ws`, verified against the real binary in a NixOS VM test. The May design's Node.js fallback (§4.5) is dropped.

The May design and its §4.5 are not in this repository. §4.5 was the Node.js fallback (a helper using `@holochain/client`) of the May design's installer decision, ADR-004, which is not published here (see the [index](README.md)).

## Consequences

The record states no consequences beyond the decision itself.

## Later record

- On the 0.6 line, which [ADR-007](0007-toolchain-pins.md) as amended added, the same admin calls run under `hc sandbox call --running <adminPort>`: the 0.6.3 `hc` has no `client` subcommand. This is recorded in [#16](https://github.com/Sensorica/nixos-holochain/pull/16) and re-derived in its [review](https://github.com/Sensorica/nixos-holochain/pull/16#issuecomment-5450312198), and it is what `modules/holochain-edgenode.nix` does on `main`.
