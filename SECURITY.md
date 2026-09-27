# Security policy

This repository ships NixOS modules that run a Holochain conductor, its keystore, and the services around it on machines other people own. A flaw here lands on every node built from it, so please report it privately first.

## Supported versions

| Version | Supported |
| --- | --- |
| `main` | Yes |
| Latest release line, once one exists | Yes |
| Anything older | No |

There is no release of the modules yet, so today only `main` receives fixes. From the first release on, the latest release line is supported alongside `main`, and fixes land on `main` first.

## Reporting a vulnerability

Report it through GitHub's private vulnerability reporting: open the repository's **Security** tab and choose **Report a vulnerability**, or go straight to <https://github.com/Sensorica/nixos-holochain/security/advisories/new>. The report is visible only to you and the maintainers.

Please do not open a public issue, pull request or discussion for a vulnerability until a fix is released.

A useful report says:

- which module and which options are involved (`services.holochain-edgenode`, `services.holochain-grafana`, `services.holochain-http-gateway` or `services.holochain-windtunnel`),
- the nixos-holochain commit your flake is locked to (`nix flake metadata` lists it under Inputs),
- what an attacker can do, from where, and what they need first,
- the steps or configuration that reproduce it.

## What counts

Anything in this repository that weakens the machines it configures, for example:

- a secret (lair passphrase, Grafana admin password or secret key, private key) written into the world-readable Nix store or into git,
- a default or an option combination that exposes the conductor admin interface, or another local-only interface, beyond the machine,
- a firewall port opened that the options did not ask for,
- a generated systemd unit, file or directory with broader permissions than it needs.

A vulnerability in Holochain, lair, Grafana, Prometheus or NixOS itself belongs with that project. If you are unsure whether the fault is ours or upstream, report it here and we will route it.

## What happens next

A maintainer acknowledges the report, works out a fix with you in the private advisory, and publishes the advisory with the fix. The maintainers are volunteers, so there is no guaranteed response time; if a report seems to have gone unnoticed, comment on the advisory again.
