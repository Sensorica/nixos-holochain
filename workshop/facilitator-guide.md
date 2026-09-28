# Facilitator Guide

**Audience:** People who can already use a terminal and have heard of Holochain. No Nix experience required.
**Duration:** 4 hours.
**Outcome:** Each participant deploys a working edgenode and watches the fleet exchange messages.
**Format:** Pre-flight sent one week before + facilitated session.

---

## The 4-hour arc

| Time | Segment | Goal |
|------|---------|------|
| 0:00 to 0:30 | **Conceptual intro** | Declarative vs imperative. Why this matters for Holochain. Fractal sovereignty framing if the room is receptive. |
| 0:30 to 1:15 | **Flake walkthrough** | Open the repo in Kate. Walk through `flake.nix`, the module, a host config. Show option discovery via `nix repl`. |
| 1:15 to 2:15 | **First deploy** | Each participant boots, clones the repo, runs `sudo nixos-rebuild switch --flake .#sensorica-holoport-0N` from `examples/sensorica-fleet` (`rebuild` on an installed Holoport). Conductor visible via `systemctl status`. |
| 2:15 to 3:15 | **Observe** | Open Grafana's room screen and watch the fleet's traffic: the five conductors running hREA, Kando and Requests & Offers on one network seed. Wind Tunnel is not part of this: it feeds nothing to Grafana (see docs/architecture.md § What the Wind Tunnel runner is, and is not). |
| 3:15 to 3:45 | **Modify, rollback, join Moss** | Change a hApp property, redeploy, then `sudo nixos-rebuild switch --rollback`. This is where the "aha" usually lands. Then have participants open Moss on their laptop and join the group hosted by the fleet. |
| 3:45 to 4:00 | **Q&A + next steps** | How to extend the module. How to contribute back. Where the project goes from here. |

---

## Why KDE Plasma 6 on participant machines

Workshop nodes ship with KDE Plasma 6 as the desktop. Reasoning:

- **Familiar paradigm.** Most participants recognize KDE (taskbar, file manager, settings GUI). Lower cognitive load means more attention available for Nix concepts.
- **Dolphin is a discoverability tool.** Participants can browse the flake repo visually, see the file structure, click into modules. Helps cement "the flake is just files."
- **Kate + Konsole + Firefox side by side.** Kate gets Nix syntax highlighting via the `nil` or `nixd` LSP. Konsole runs `nixos-rebuild`. Firefox holds `search.nixos.org/options`. Productive layout for learning.
- **Plasma 6 on NixOS is mature.** Solid as of 2026.

---

## Facilitation notes

- **Option A vs B trade-off.** Option A (pre-baked module, participants are users) is what this workshop does. Option B (live module authoring) is more interesting but riskier and only works for groups already comfortable with Nix. For 5-machine fleets with mixed audiences, A wins.
- **Deployment tool.** `colmena apply --impure --on @all` for parallel deploys (`--impure`: see the fleet README). Plain `nixos-rebuild switch --target-host` if colmena feels like too much.
- **Network reality.** Test the workshop network in advance. The December 2025 HolOS workshop was bitten by this. Bring a dedicated router.
- **Grafana moment.** This is the high point of the workshop. Make sure the room screen shows the three hApps In step on every machine before flipping it to the big screen.

---

## Common failure modes and fixes

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `holochain-conductor.service` fails immediately | Conductor or keystore error | Check `journalctl -u holochain-conductor`; the unit creates its lair passphrase itself on first boot, so no init step is missing |
| `holochain-happ-installer.service` fails | An app did not install or enable within `installerTimeout` (900 s on the fleet); the first boot compiles three hApps | `journalctl -u holochain-happ-installer`, then `systemctl restart holochain-happ-installer`. Bundles are fetched by hash when the system is built, never read from `happs/` |
| Participants can't see each other's nodes | Firewall closed | Ensure `openFirewall = true` and router is not blocking DHT traffic |
| `colmena apply` can't reach nodes | SSH keys not set up | Add the facilitator's SSH key to `operatorKeys` in `examples/sensorica-fleet/hosts/common.nix` before building |
| Live USB drops to emergency mode, "Expecting device /dev/disk/by-label/nixos-graphical-…" | Stick made with Ventoy | Write the ISO with `dd` and check it with `cmp`; see docs/deployment.md § Rescuing an install |
| Installer fails on `cache.nixos.org … after 0 ms` | Router DNS answers IPv6 only, no IPv6 route | Public DNS on the live session with `nmcli`, then retry; see docs/deployment.md § Rescuing an install |
| Installer offers only manual partitioning on retry | Previous failed run still mounted | Unmount `/tmp/calamares-root-*` and `swapoff -a`, relaunch |
| Installer failed and the reason is unclear | Calamares hides `nixos-install` output | SSH in from a laptop and read `/root/.cache/calamares/session.log`; see docs/deployment.md § Rescuing an install |

---

## Lessons from December 2025 (HolOS workshop)

See `docs/archive/` for the original workshop notes. Key takeaways:

- Lab wifi is not reliable for P2P DHT traffic. Dedicated router is mandatory.
- HolOS image installation was faster but didn't give participants the authoring experience — they flashed a pre-built Buildroot image rather than configuring their own stack. Participants felt they were watching, not building.
- 4 hours was the right duration. Longer risks losing the room after the Grafana moment.
