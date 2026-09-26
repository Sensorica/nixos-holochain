# happs/

`.happ` bundles are **not** committed to this repository (ADR-012). Nothing in the flake reads from this directory any more; it exists to document where bundles come from and how to point the module at one.

## Referencing a hApp

Fetch it by hash, so the configuration is reproducible and the bundle stays out of git:

```nix
services.holochain-edgenode.happs = {
  dino-adventure = {
    src = pkgs.fetchurl {
      url = "https://github.com/holochain/dino-adventure/releases/download/v0.3.0/dino-adventure-v0.3.0.happ";
      sha256 = "4dd11f7c5f5ee73f9472827e48ab3538f53f37f819af610bf8de95c10ee74f72";
    };
    networkSeed = "workshop-2026";
  };
};
```

The attribute name is the installed app id: it is what `install-app --app-id` is given and what `list-apps` reports back.

To get the hash of a bundle you have not used before:

```bash
nix-prefetch-url --type sha256 <url>   # base32
# or, from a local file
sha256sum <file>
```

## Bundles the VM tests use

Both are published releases, fetched by hash in `flake.nix`:

| Bundle | Line | Used by | sha256 |
|---|---|---|---|
| [Dino Adventure v0.3.0](https://github.com/holochain/dino-adventure/releases/download/v0.3.0/dino-adventure-v0.3.0.happ) | 0.7.0 | `checks.vmTestWithHapp` | `4dd11f7c5f5ee73f9472827e48ab3538f53f37f819af610bf8de95c10ee74f72` |
| [Kando v0.17.5](https://github.com/holochain-apps/kando/releases/download/v0.17.5/kando.happ) | 0.6.3 | `checks.vmTestWithHapp-0_6` | `a4cdee64fe32720077e0aade94630f24d0da5e91da33ccbe5bfd894d9d359f28` |

Neither test is conditional. An earlier version of `vmTestWithHapp` was gated on `builtins.pathExists ./happs/windtunnel.happ`, which meant it silently did not exist: a flake only sees git-tracked files, and `*.happ` is gitignored.

## Workshop bundles

| Bundle | Source | Purpose |
|---|---|---|
| Wind Tunnel | [holochain/wind-tunnel](https://github.com/holochain/wind-tunnel) | Observable traffic for the Grafana moment (slice 3) |
| Moss | [lightningrodlabs/moss](https://github.com/lightningrodlabs/moss) | Participants join the group from their own laptop after the workshop |

Check each project's releases for a bundle built against the Holochain line the fleet runs. As of this writing Wind Tunnel, hREA, Requests & Offers and Nondominium all still publish 0.6.x bundles; only Moss 0.16-dev targets 0.7.
