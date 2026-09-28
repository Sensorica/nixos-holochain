# ADR-007: Toolchain pins

- **Status:** Amended (2026-08-28, dual-line)
- **Date:** 2026-08-28
- **Source:** [#1](https://github.com/Sensorica/nixos-holochain/issues/1), issue description, section "Decisions (ADRs, continuing the numbering of the May design doc)"; amendment from [#15](https://github.com/Sensorica/nixos-holochain/issues/15), issue description, section "6. Decisions (ADR amendments, effective now)", copied into #1 under "Amendments from the research record"

## Context

From the state of the repository recorded in #1 when the decision was taken (verified 2026-08-28):

> Holochain 0.7.0 is released; holonix branch `main-0.7` is the target. The lock pins `main` from May, which resolved to a dev build.

## Decision

> holonix input is `github:holochain/holonix/main-0.7`. nixpkgs is `nixos-25.05` to match `system.stateVersion`, unless a required module only exists on unstable, in which case the Builder records the reason in the PR and bumps `stateVersion` consistently.

## Consequences

The record states no consequences beyond the decision itself.

## Amendments

### 2026-08-28: the module is dual-line

From #15, section 6:

> Root inputs `holonix` (`main-0.7`, the default package) and `holonix-0_6` (`main-0.6`, 0.6.3). The module renders the conductor `network` section from the package version: `lib.versionOlder cfg.package.version "0.7"` → `bootstrap_url` + `signal_url` (0.6, kitsune2/sbd; production defaults taken from edgenode's `conductor-config-0.6.1.template.yaml`); otherwise `bootstrap_url` + `relay_url` (0.7, Iroh; defaults from `holochain --create-config`). Option `signalUrl` stays for 0.6 and is ignored with a warning on 0.7; new option `relayUrl`. Both lines get a VM smoke test (`vmTest`, `vmTest-0_6`) and a hApp test (`vmTestWithHapp` with Dino Adventure v0.3.0 on 0.7; `vmTestWithHapp-0_6` with Kando v0.17.5 or hREA happ-0.4.0-beta on 0.6), all fetched by sha256. Reason: the release train is 0.7 and that is what a community user adopting the module next month should get by default, while every hApp with real content still targets 0.6.x; a module that serves only one line serves nobody in September 2026.

Its context, from #15 section 1: Holochain 0.7.0 was released 2026-07-30 with Iroh over QUIC as the only transport (`signal_url` must be removed from conductor configs) and no data migration from 0.6.

## Later record

- **0.6 network section.** [#16](https://github.com/Sensorica/nixos-holochain/pull/16) found that a 0.6.3 conductor given only `bootstrap_url` + `signal_url` refuses to start with `network: missing field 'relay_url'`, so the module renders `bootstrap_url` + `signal_url` + `relay_url` below 0.7 and `bootstrap_url` + `relay_url` from 0.7. The [review](https://github.com/Sensorica/nixos-holochain/pull/16#issuecomment-5450312198) re-derived this from edgenode's 0.6.1 template. #1 was not amended.
- **nixpkgs.** [#20](https://github.com/Sensorica/nixos-holochain/pull/20) moved the root flake, both templates and the example to `nixos-26.05`, with `system.stateVersion = "26.05"`, because `nixos-25.05` reached end of life. #1 was not amended; `flake.nix` on `main` pins `nixos-26.05`.
