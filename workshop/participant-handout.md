# Participant Handout — Holochain Edgenode Workshop

**Sensorica Lab, August 2026**

---

## What we are building today

By the end of this session you will have:

- A working Holochain edgenode running on a real machine, declared entirely in a single Nix file
- Deployed that node into a 5-machine fleet using a single command
- Watched live P2P traffic between all nodes using Wind Tunnel + Grafana
- Rolled back a configuration change in under 10 seconds

---

## The loop you will learn

```
Edit configuration.nix in Kate
        ↓
sudo nixos-rebuild switch --flake .#edgenode-0X
        ↓
systemctl status holochain-conductor
        ↓
# if something breaks:
sudo nixos-rebuild --rollback
```

That is the whole practice. Everything else is understanding what lives in `configuration.nix`.

---

## Key files in the repo

```
nixos-holochain/
├── flake.nix                          # Root: declares inputs and all system outputs
├── modules/holochain-edgenode.nix     # The module you are using
└── hosts/edgenode-0X/configuration.nix  # Your machine's config — edit this
```

---

## Useful commands

| Command | What it does |
|---------|-------------|
| `nixos-rebuild switch --flake .#edgenode-01` | Rebuild and switch to new config |
| `nixos-rebuild --rollback` | Roll back to previous generation |
| `systemctl status holochain-conductor` | Check conductor health |
| `journalctl -u holochain-conductor -f` | Follow conductor logs |
| `nix repl --file '<nixpkgs>'` | Explore available options interactively |
| `nixos-option services.holochain-edgenode` | View module options |

---

## After the workshop

The repo stays alive. You can keep your edgenode running, add your own hApps, or contribute a new module.

- GitHub: https://github.com/Sensorica/nixos-holochain
- Issues welcome for bugs, questions, and module ideas
