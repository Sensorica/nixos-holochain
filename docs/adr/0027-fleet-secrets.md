# ADR-027: What is sensitive in a fleet, and how it is kept

- **Status:** Accepted
- **Date:** 2026-11-15
- **Source:** AD10 of the architecture review of 2026-11-07 and 2026-11-15, summarised in [#98](https://github.com/Sensorica/nixos-holochain/issues/98)

## Context

Measured on 2026-11-15: no credential is in git.
Passwords, the Headscale key and the Grafana password are files read at runtime under `/var/lib/secrets`, never committed ([ADR-012](0012-nothing-binary-or-secret-in-git.md)), and `secrets/` is ignored by git except for `*.example` files.
The hardware files are templates, not `nixos-generate-config` output, and no public IP or MAC address is tracked.
What is sensitive is the topology: LAN addresses, public names, open ports, an event mode with password-less login.

## Options considered

- **A private repository, with credentials kept out of git as ignored files (`.env` or `/var/lib/secrets`) placed by hand on each machine.**
  No new dependency, and ADR-012 holds as it is.
  Placing a secret again on a reinstalled machine stays a manual step.
- **A private repository, plus git-crypt on the files that carry the topology.**
  Even read access to the private repository does not reveal the map without the key, but every contributor needs the key and an encrypted diff cannot be reviewed on GitHub.
- **A private repository, plus agenix or sops-nix to deliver encrypted credentials to the machines.**
  Secrets are versioned and deployed with the fleet, with no file placed by hand, at the cost of a host key per machine and one more module.

## Decision

The fleet lives in a private repository ([ADR-020](0020-fleet-in-a-private-repository.md)), and credentials stay out of git, as ignored files placed by hand on each machine.

### Why

The private repository takes care of the topology, and the credentials are already out of git.
git-crypt guards against a member of the organisation reading the repository, which is not today's threat.
agenix is the right next step once the fleet grows past five machines.
