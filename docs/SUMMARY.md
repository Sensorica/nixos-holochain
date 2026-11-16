# Summary

[Introduction](introduction.md)

# Installing a Holoport

- [Deployment guide](deployment.md)
- [The Sensorica Lab fleet](sensorica-fleet.md)
- [Workshop participant handout](workshop/participant-handout.md)
- [Workshop pre-flight checklist](workshop/preflight-checklist.md)
- [Workshop facilitator guide](workshop/facilitator-guide.md)

# Running the modules

- [Getting started](getting-started.md)
- [Architecture](architecture.md)
- [Module options](module-options.md)
- [Starting from a template]()
  - [One edgenode](templates/minimal.md)
  - [A fleet](templates/fleet.md)
- [hApp bundles](happs.md)
- [Moss always-online node](moss-node.md)
- [The Moss pilot's node and bootstrap server](pilot-node.md)
- [Admin plane: Headscale and a public Grafana](admin-plane.md)

# Contributing

- [Contributing](contributing.md)
- [Releasing](releasing.md)
- [Architecture decision records](adr/README.md)
  - [ADR-005: Fleet becomes an example](adr/0005-fleet-becomes-an-example.md)
  - [ADR-006: Installer on hc client call](adr/0006-installer-on-hc-client-call.md)
  - [ADR-007: Toolchain pins](adr/0007-toolchain-pins.md)
  - [ADR-008: Traffic and metrics](adr/0008-traffic-and-metrics.md)
  - [ADR-009: HTTP gateway](adr/0009-http-gateway.md)
  - [ADR-010: Stack shape](adr/0010-stack-shape.md)
  - [ADR-011: CI policy](adr/0011-ci-policy.md)
  - [ADR-012: Nothing binary or secret in git](adr/0012-nothing-binary-or-secret-in-git.md)
  - [ADR-013: Hardware-bound acceptance stays with the principal](adr/0013-hardware-bound-acceptance-stays-with-the-principal.md)
  - [ADR-014: Verification modality](adr/0014-verification-modality.md)
  - [ADR-015: The Sensorica fleet pins 0.6.3 for the September workshop](adr/0015-sensorica-fleet-pins-0-6-3.md)
  - [ADR-016: Passphrase and readiness follow Holo's module](adr/0016-passphrase-and-readiness.md)
  - [ADR-017: HoloPort is a legacy-BIOS x86_64 target](adr/0017-holoport-legacy-bios-target.md)
  - [ADR-018: Split flake.nix into flake-parts modules](adr/0018-split-flake-nix.md)
  - [ADR-019: Three module layers, and the lab's pieces leave the generic flake](adr/0019-three-module-layers.md)
  - [ADR-020: The lab's fleet and workshop move to a private repository](adr/0020-fleet-in-a-private-repository.md)
  - [ADR-021: A registry of Holochain and Moss lines](adr/0021-line-registry.md)
  - [ADR-022: Observability is one unit](adr/0022-observability-unit.md)
  - [ADR-023: A fleet layer for the admin plane and remote access](adr/0023-fleet-layer.md)
  - [ADR-024: Several Moss nodes on one machine](adr/0024-moss-node-instances.md)
  - [ADR-025: One option namespace before v0.1](adr/0025-one-option-namespace.md)
  - [ADR-026: The flake split first, the open branches rebased on it](adr/0026-order-of-work.md)
  - [ADR-027: What is sensitive in a fleet, and how it is kept](adr/0027-fleet-secrets.md)
  - [ADR-028: The public history is kept](adr/0028-keep-public-history.md)
  - [ADR-029: v0.1.0 is the first community release](adr/0029-v0-1-0-community-release.md)
  - [ADR-030: The option prefix](adr/0030-option-prefix.md)
- [Archive: December 2025 HolOS workshop](archive/README.md)
