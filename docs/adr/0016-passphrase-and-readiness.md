# ADR-016: Passphrase and readiness follow Holo's module

- **Status:** Accepted
- **Date:** 2026-08-28
- **Source:** [#15](https://github.com/Sensorica/nixos-holochain/issues/15), issue description, section "6. Decisions (ADR amendments, effective now)"; summarised in [#1](https://github.com/Sensorica/nixos-holochain/issues/1) under "Amendments from the research record"

## Context

From #15, section 5:

> [Holo-Host/holo-host](https://github.com/Holo-Host/holo-host) `nix/modules/nixos/holochain/default.nix` (pushed 2026-07-03): options under `holo.holochain`, default package holonix 0.5 (behind), `passphraseFile` generated with `pwgen` in `preStart`, `holochain --piped --config-path … < passphrase`, `Type = "notify"` (the conductor does `sd_notify`), `StateDirectory` mode 0700, `Restart = always`. A sibling `hc-http-gw/` module exists next to it. This is the closest prior art and the reference for our passphrase and readiness handling.

## Decision

> Slice 2 generates the lair passphrase in `preStart` into `$STATE_DIRECTORY` (mode 0600, `pwgen` or `openssl rand`), feeds it with `holochain --piped < file`, uses `Type = "notify"` (verify the conductor's `sd_notify` in the VM; fall back to the port poll only if it does not fire), `StateDirectory` 0700. Credit Holo-Host/holo-host in `docs/architecture.md`.

## Consequences

From #15, section 7, for slice 2 ([#3](https://github.com/Sensorica/nixos-holochain/issues/3)): "passphrase per ADR-016".

## Later record

- [#16](https://github.com/Sensorica/nixos-holochain/pull/16) reports `Type = "notify"` proven in the VM (systemd prints `Started Holochain conductor.` only after the conductor's readiness signal), so the port-poll fallback was not needed. On `main`, `modules/holochain-edgenode.nix` runs the conductor as `Type = "notify"` by default through the `useSystemdNotify` option, with `Type = "simple"` when it is set to false.
- The credit is in [docs/architecture.md § The lair passphrase and readiness](../architecture.md#the-lair-passphrase-and-readiness).
