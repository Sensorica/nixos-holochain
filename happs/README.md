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
