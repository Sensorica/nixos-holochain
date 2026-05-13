# Module Options Reference

This document will be auto-generated from module options once the build is stable.
Until then, options are documented inline in each module file.

## holochain-edgenode

See `modules/holochain-edgenode.nix` for the full option set.

Quick reference:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable the edgenode service |
| `package` | package | holonix holochain | Conductor package |
| `user` | string | `"holochain"` | System user |
| `dataDir` | path | `/var/lib/holochain` | Persistent state directory |
| `adminPort` | port | 4444 | Admin WebSocket port |
| `appPort` | port | 8888 | App WebSocket port |
| `allowedOrigins` | string | `"*"` | Allowed origins |
| `bootstrapUrl` | string | holo.host bootstrap | Bootstrap server URL |
| `signalUrl` | string | holo.host signal | Signal server URL |
| `happs` | attrs | `{}` | hApps to install at first boot |
| `openFirewall` | bool | false | Open firewall ports |

## holochain-windtunnel

Placeholder — see module file for current status.

## holochain-http-gateway

Placeholder — see module file for current status.

## pai

Placeholder — see module file for current status.
