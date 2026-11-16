# ADR-028: The public history is kept

- **Status:** Accepted
- **Date:** 2026-11-15
- **Source:** AD11 of the architecture review of 2026-11-07 and 2026-11-15, summarised in [#98](https://github.com/Sensorica/nixos-holochain/issues/98)

## Context

Moving the fleet removes nothing from the history: since September, public commits carry the lab's name, its LAN address plan and its public names.
No credential was found in it (a search of the whole history found no secret file and no public IP).

## Options considered

- **Keep the history, and change what is already public as soon as it matters (LAN addresses, host names).**
  No rewrite, and clones and links to commits keep working; what was published stays readable to anyone who digs.
- **Rewrite the history with `git filter-repo` to remove the fleet and the lab's files before announcing the repository.**
  The public repository is born clean, at the cost of a force-push to `main`, every existing clone starting over, and broken links to old commits from issues and pull requests.
- **Start a new public repository, and archive this one as private.**
  A clean history without rewriting this one, but the issues, pull requests and stars stay on the old one.

## Decision

The history is kept; what is already public changes when it matters.

### Why

What the history holds is a private LAN topology and DNS names anyone can already resolve, not a key.
Rewriting a public repository's history is irreversible and breaks the deployed machines' clones; it would only be worth it if a credential had leaked, and the search found none.
