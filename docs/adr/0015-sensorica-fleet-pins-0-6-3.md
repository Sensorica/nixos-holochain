# ADR-015: The Sensorica fleet pins 0.6.3 for the September workshop

- **Status:** Accepted
- **Date:** 2026-08-28
- **Source:** [#15](https://github.com/Sensorica/nixos-holochain/issues/15), issue description, section "6. Decisions (ADR amendments, effective now)"; summarised in [#1](https://github.com/Sensorica/nixos-holochain/issues/1) under "Amendments from the research record"

"The principal" in the record is @Soushi888.

## Context

From #15, section 6, the reason given for [ADR-007](0007-toolchain-pins.md) as amended:

> the release train is 0.7 and that is what a community user adopting the module next month should get by default, while every hApp with real content still targets 0.6.x

#15, section 3, lists the downloadable bundles per line: on 0.7.0, Dino Adventure v0.3.0 and Moss `group.happ` 0.16-dev.3; on 0.6.x, hREA happ-0.4.0-beta, Kando v0.17.5, Requests & Offers v0.5.2 (`.webhapp` only) and others.

## Decision

> **ADR-015 (new): the Sensorica fleet pins 0.6.3 for the September workshop**, with hREA happ-0.4.0-beta, Kando v0.17.5 and Requests & Offers v0.5.2 (unpacked) as the fleet's hApps, Kando desktop and Moss 0.15.8 on participants' laptops for the "join from your laptop" step. Dino Adventure stays the 0.7 CI fixture. Re-evaluated seven days before the date: if Moss 0.16 is stable and hREA or R&O have shipped 0.7 bundles by then, the example flips to 0.7. The principal can override this pin at any time; it is a workshop decision, not a module decision.

## Consequences

From #15, section 7, for slice 5 ([#6](https://github.com/Sensorica/nixos-holochain/issues/6)): "fleet hApps per ADR-015; participant laptop step uses Kando desktop / Moss 0.15.8".

From #15, section 8, open question: "Whether the principal wants the fleet on 0.7 regardless of the thin hApp menu (ADR-015 is reversible with one line)."
