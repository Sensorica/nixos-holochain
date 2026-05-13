# happs/

Place compiled `.happ` bundles here. They are referenced by host configurations via relative paths.

## Adding a hApp

1. Build or download the `.happ` file.
2. Drop it in this directory.
3. Reference it in your host config:

```nix
services.holochain-edgenode.happs = {
  my-app = {
    src = ../../happs/my-app.happ;
    networkSeed = "my-network-seed-2026";
  };
};
```

## Workshop hApps

| File | Source | Purpose |
|------|--------|---------|
| `windtunnel.happ` | [holochain/wind-tunnel](https://github.com/holochain/wind-tunnel) | Observable traffic for the Grafana moment |
| `moss.happ` | [lightningrodlabs/moss](https://github.com/lightningrodlabs/moss) | Participants can join the group from their own laptop after the workshop |

hApp files are not committed to this repo (they can be large). Fetch them before the workshop using the preflight checklist.

## Phase 1 requirements

`windtunnel.happ` must be present for:
- **P1-03** — `holochain-happ-installer.service` validation on a physical machine
- **`checks.vmTestWithHapp`** — the hApp installer NixOS VM test (auto-skipped when file is absent)

`moss.happ` is optional for Phase 1 and required for Phase 2 (workshop fleet).

### Fetching the bundles

```bash
# Wind Tunnel — check the Releases page for the latest .happ asset
# https://github.com/holochain/wind-tunnel/releases
curl -L -o happs/windtunnel.happ \
  https://github.com/holochain/wind-tunnel/releases/latest/download/windtunnel.happ

# Moss — check the Releases page for the latest .happ asset
# https://github.com/lightningrodlabs/moss/releases
curl -L -o happs/moss.happ \
  https://github.com/lightningrodlabs/moss/releases/latest/download/moss.happ
```

After downloading, record the SHA-256 checksums here for reproducibility:

| File | SHA-256 |
|------|---------|
| `windtunnel.happ` | *(fill in after download: `sha256sum happs/windtunnel.happ`)* |
| `moss.happ` | *(fill in after download: `sha256sum happs/moss.happ`)* |

### .gitignore

`.happ` files are excluded from version control. Confirm the repo `.gitignore` contains:

```
happs/*.happ
```
