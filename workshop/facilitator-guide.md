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
| 1:15 to 2:15 | **First deploy** | Each participant boots, clones the repo, runs `nixos-rebuild switch --flake .#minimal`. Conductor visible via `systemctl status`. |
| 2:15 to 3:15 | **Add Wind Tunnel + observe** | Flip `services.holochain-windtunnel.enable = true`. Redeploy. Open Grafana, watch fleet traffic light up. |
| 3:15 to 3:45 | **Modify, rollback, join Moss** | Change a hApp property, redeploy, then `nixos-rebuild --rollback`. This is where the "aha" usually lands. Then have participants open Moss on their laptop and join the group hosted by the fleet. |
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
- **Deployment tool.** `colmena apply --on @all` for parallel deploys. Plain `nixos-rebuild switch --target-host` if colmena feels like too much.
- **Network reality.** Test the workshop network in advance. The December 2025 HolOS workshop was bitten by this. Bring a dedicated router.
- **Grafana moment.** This is the high point of the workshop. Make sure Wind Tunnel is generating visible traffic before flipping the dashboard to the big screen.

---

## Common failure modes and fixes

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `holochain-conductor.service` fails immediately | Lair keystore not initialized | Check `journalctl -u holochain-conductor` for lair errors; may need a first-boot init step |
| `happ-installer.service` fails silently | hApp file not found at path | Verify `happs/` contains the `.happ` files before ISO build |
| Participants can't see each other's nodes | Firewall closed | Ensure `openFirewall = true` and router is not blocking DHT traffic |
| `colmena apply` can't reach nodes | SSH keys not set up | Add facilitator SSH key to each host config before building |

---

## Lessons from December 2025 (HolOS workshop)

See `docs/archive/` for the original workshop notes. Key takeaways:

- Lab wifi is not reliable for P2P DHT traffic. Dedicated router is mandatory.
- HolOS image installation was faster but removed all operator control. Participants felt they were watching, not building.
- 4 hours was the right duration. Longer risks losing the room after the Grafana moment.
