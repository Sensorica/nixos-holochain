# holochain-nixos

> A declarative substrate for running Holochain edgenodes, hApps, and developer environments. Built at Sensorica, intended for the Holochain community.

**Status:** Pre-alpha. Workshop substrate under construction.
**License:** TBD (suggest CAL or AGPL aligned with OVN License direction)
**Origin:** Successor to the archived [Sensorica/holoports-workshop](https://github.com/Sensorica/holoports-workshop), pivoting from HolOS appliance-image deployment to vanilla NixOS authorship.

---

## 1. Why this exists

The Holochain ecosystem has two real deployment stories today:

1. **Dev environments via Holonix** (Nix-based, well documented, mature)
2. **Production edgenodes via HolOS** (a Buildroot-based appliance image: you flash and run it, not author it)

There is no canonical, declarative, *author it yourself* way to stand up a Holochain edgenode on commodity hardware. You either flash the HolOS pre-built image (without authoring the configuration) or you cobble together systemd units, conductor configs, and lair keystore management by hand.

`holochain-nixos` fills that gap. A flake-based repo with reusable NixOS modules so that:

* Stewards of OVNs (Sensorica, AlterNef, others) can deploy production node fleets with a single `nixos-rebuild`.
* The Holochain community gets a reference implementation for declarative edgenode hosting.
* Workshops can teach the full stack in 4 hours instead of demoing pre baked images.

The architectural bet is simple. HolOS gives you a minimal Buildroot image to flash. This project takes the opposite approach: declarative NixOS configuration you own, so the community can compose Holochain with the rest of their infrastructure rather than around it.

---

## 2. What's in the box

```
holochain-nixos/
├── flake.nix                          # Entry point, inputs, outputs
├── flake.lock
├── README.md                          # This file (or trimmed version)
│
├── modules/
│   ├── holochain-edgenode.nix         # Conductor + lair + happ installer
│   ├── holochain-windtunnel.nix       # Wind Tunnel scenario runner
│   ├── holochain-http-gateway.nix     # HTTP gateway in front of conductor
│   ├── pai.nix                        # Optional: PAI per machine
│   └── default.nix                    # Module aggregator
│
├── hosts/
│   ├── edgenode-01/configuration.nix  # Fleet member 1
│   ├── edgenode-02/configuration.nix
│   ├── edgenode-03/configuration.nix
│   ├── edgenode-04/configuration.nix
│   ├── edgenode-05/configuration.nix
│   └── workshop-iso/configuration.nix # Live ISO for participants
│
├── happs/
│   ├── windtunnel.happ                # Or fetched via flake input
│   ├── moss.happ                      # Moss / The Weave frame
│   └── README.md                      # How to add a new hApp
│
├── lib/
│   └── default.nix                    # Helper functions
│
├── workshop/
│   ├── facilitator-guide.md           # Sections 5 to 7 of this doc
│   ├── participant-handout.md
│   └── preflight-checklist.md
│
├── docs/
│   ├── architecture.md
│   ├── module-options.md              # Auto generated from module options
│   └── deployment.md
│
└── examples/
    ├── minimal/                       # Just a conductor, no extras
    ├── moss-group/                    # Edgenode hosting a Moss group
    └── developer-laptop/              # Full dev env (Holonix + IDE)
```

---

## 3. The flake skeleton

```nix
# flake.nix
{
  description = "Declarative NixOS modules for Holochain edgenodes and dev environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    holonix.url = "github:holochain/holonix";
    flake-parts.url = "github:hercules-ci/flake-parts";
    colmena.url = "github:zhaofengli/colmena";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];

      flake = {
        # Reusable modules for downstream consumers
        nixosModules = {
          holochain-edgenode = ./modules/holochain-edgenode.nix;
          holochain-windtunnel = ./modules/holochain-windtunnel.nix;
          holochain-http-gateway = ./modules/holochain-http-gateway.nix;
          pai = ./modules/pai.nix;
          default = ./modules;
        };

        # Concrete fleet of 5 workshop nodes
        nixosConfigurations = let
          mkEdgenode = name: nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./hosts/${name}/configuration.nix
              self.nixosModules.holochain-edgenode
            ];
            specialArgs = { inherit inputs; };
          };
        in {
          edgenode-01 = mkEdgenode "edgenode-01";
          edgenode-02 = mkEdgenode "edgenode-02";
          edgenode-03 = mkEdgenode "edgenode-03";
          edgenode-04 = mkEdgenode "edgenode-04";
          edgenode-05 = mkEdgenode "edgenode-05";

          # Bootable ISO for workshop participants
          workshop-iso = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ./hosts/workshop-iso/configuration.nix
            ];
          };
        };

        # Colmena fleet deployment
        colmena = {
          meta = {
            nixpkgs = import nixpkgs { system = "x86_64-linux"; };
            specialArgs = { inherit inputs; };
          };
          edgenode-01 = { ... }: { imports = [ ./hosts/edgenode-01/configuration.nix ]; };
          edgenode-02 = { ... }: { imports = [ ./hosts/edgenode-02/configuration.nix ]; };
          edgenode-03 = { ... }: { imports = [ ./hosts/edgenode-03/configuration.nix ]; };
          edgenode-04 = { ... }: { imports = [ ./hosts/edgenode-04/configuration.nix ]; };
          edgenode-05 = { ... }: { imports = [ ./hosts/edgenode-05/configuration.nix ]; };
        };
      };

      perSystem = { config, pkgs, ... }: {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ nixos-rebuild colmena nil nixd alejandra ];
        };
      };
    };
}
```

---

## 4. The core module: `holochain-edgenode.nix`

This is the contribution. A first sketch of the public API:

```nix
# modules/holochain-edgenode.nix
{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.holochain-edgenode;
  conductorConfig = pkgs.writeText "conductor-config.yaml" ''
    # Generated by holochain-edgenode module
    data_root_path: ${cfg.dataDir}
    keystore:
      type: lair_server_in_proc
    admin_interfaces:
      - driver:
          type: websocket
          port: ${toString cfg.adminPort}
          allowed_origins: ${cfg.allowedOrigins}
    network:
      bootstrap_url: ${cfg.bootstrapUrl}
      signal_url: ${cfg.signalUrl}
  '';
in {
  options.services.holochain-edgenode = {
    enable = lib.mkEnableOption "Holochain edgenode (conductor + lair + hApp installer)";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.holonix.packages.${pkgs.system}.holochain;
      description = "Holochain conductor package";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "holochain";
      description = "User the conductor runs as";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/holochain";
      description = "Persistent state directory";
    };

    adminPort = lib.mkOption {
      type = lib.types.port;
      default = 4444;
    };

    appPort = lib.mkOption {
      type = lib.types.port;
      default = 8888;
    };

    allowedOrigins = lib.mkOption {
      type = lib.types.str;
      default = "*";
    };

    bootstrapUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://bootstrap.holo.host";
    };

    signalUrl = lib.mkOption {
      type = lib.types.str;
      default = "wss://signal.holo.host";
    };

    happs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          src = lib.mkOption { type = lib.types.path; };
          installed = lib.mkOption { type = lib.types.bool; default = true; };
          networkSeed = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
        };
      });
      default = {};
      description = "hApps to install at first boot, keyed by app id";
      example = lib.literalExpression ''
        {
          windtunnel = {
            src = ./happs/windtunnel.happ;
            networkSeed = "workshop-2026";
          };
          moss = {
            src = ./happs/moss.happ;
            networkSeed = "sensorica-moss-2026";
          };
        }
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = cfg.dataDir;
      createHome = true;
    };
    users.groups.${cfg.user} = {};

    systemd.services.holochain-conductor = {
      description = "Holochain conductor";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.user;
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${cfg.package}/bin/holochain --config-path ${conductorConfig}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    systemd.services.holochain-happ-installer = lib.mkIf (cfg.happs != {}) {
      description = "Install configured hApps into the conductor";
      after = [ "holochain-conductor.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        RemainAfterExit = true;
      };
      script = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: happCfg: ''
        ${cfg.package}/bin/hc app install \
          --app-id ${name} \
          --path ${happCfg.src} \
          ${lib.optionalString (happCfg.networkSeed != null) "--network-seed ${happCfg.networkSeed}"} \
          --admin-port ${toString cfg.adminPort} || true
      '') cfg.happs);
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.adminPort cfg.appPort ];
    };
  };
}
```

**Open implementation questions to track as GitHub issues:**

* Lair keystore initialization on first boot (currently assumed in proc, may want a `lair-keystore.service`)
* Secrets management for network seeds (sops nix integration?)
* DHT data persistence across config changes
* How to handle conductor version upgrades without losing state
* Whether to expose `hc sandbox` style ephemeral environments

---

## 5. The workshop, concretely

**Audience:** People who can already use a terminal and have heard of Holochain. No Nix experience required.
**Duration:** 4 hours.
**Outcome:** Each participant deploys a working edgenode and watches the fleet exchange messages.
**Format:** Pre flight + facilitated session.

### 5.1 Pre flight (sent 1 week before)

```
Bring a laptop with one of:
  (a) NixOS already installed, OR
  (b) A NixOS live USB ready to boot, OR
  (c) A spare machine you can wipe (we provide USBs)

Optional but nice:
  - Ethernet cable (workshop wifi is the enemy of P2P traffic)
  - SSH client you're comfortable with
```

### 5.2 The 4 hour arc

| Time | Segment | Goal |
|------|---------|------|
| 0:00 to 0:30 | **Conceptual intro** | Declarative vs imperative. Why this matters for Holochain. Fractal sovereignty framing if the room is receptive. |
| 0:30 to 1:15 | **Flake walkthrough** | Open the repo in Kate. Walk through `flake.nix`, the module, a host config. Show option discovery via `nix repl`. |
| 1:15 to 2:15 | **First deploy** | Each participant boots, clones the repo, runs `nixos-rebuild switch --flake .#minimal`. Conductor visible via `systemctl status`. |
| 2:15 to 3:15 | **Add Wind Tunnel + observe** | Flip the `services.holochain-windtunnel.enable` option. Redeploy. Open Grafana, watch fleet traffic light up. |
| 3:15 to 3:45 | **Modify, rollback, join Moss** | Change a hApp property, redeploy, then `nixos-rebuild --rollback`. This is where the "aha" usually lands. Then have participants open Moss on their laptop and join the group hosted by the fleet. They leave with infrastructure they can keep using. |
| 3:45 to 4:00 | **Q&A + next steps** | How to extend the module. How to contribute back. Where the project goes from here. |

### 5.3 Why KDE Plasma 6 on participant machines

Workshop nodes ship with KDE Plasma 6 as the desktop. Reasoning:

* **Familiar paradigm.** Most participants recognize KDE (taskbar, file manager, settings GUI). Lower cognitive load means more attention available for Nix concepts.
* **Dolphin is a discoverability tool.** Participants can browse the flake repo visually, see the file structure, click into modules. Helps cement "the flake is just files."
* **Kate + Konsole + Firefox side by side.** Kate gets Nix syntax highlighting via the `nil` or `nixd` LSP. Konsole runs `nixos-rebuild`. Firefox holds `search.nixos.org/options`. Productive layout for learning.
* **Plasma 6 on NixOS is mature.** Solid as of 2026.

This is the canonical "edit in Kate, rebuild in Konsole" loop. There is no purer way to do NixOS. The workshop teaches the actual practice, not a sanctified version of it.

### 5.4 Facilitation notes

* **Option A vs B trade off.** Option A (pre baked module, participants are users) is what this workshop does. Option B (live module authoring) is more interesting but riskier and only works for groups already comfortable with Nix. For 5 machine fleets with mixed audiences, A wins.
* **Deployment tool.** `colmena apply --on @all` for parallel deploys. Plain `nixos-rebuild switch --target-host` if colmena feels too much.
* **Network reality.** Test the workshop network in advance. Last time this bit the team. Consider bringing a dedicated router.
* **Hardware question.** See section 7.

---

## 6. Strategic positioning

Three audiences, three framings:

* **Toward Tibi and Sensorica:** This gives Nondominium a canonical deployment story for production OVN nodes, not just dev environments. Aligns with the OVN License + protocol level enforcement direction.
* **Toward the broader Holochain community:** First NixOS native edgenode module. Real contribution. hAppenings Community Substack post writes itself once the module is stable.
* **Toward AlterNef:** The substrate of the Ship of Alternatives needs to be declarative and reproducible. This is groundwork for that, even if early.

Announce on:

* hAppenings Community Substack
* Holochain Discord (#dev channel)
* P2P Foundation Wiki (Michel Bauwens has mentioned AlterNef before)
* alternef.garden Digital Garden as a long form companion piece

---

## 7. Open decisions to make before the workshop

These need answers before the repo can stop being a sketch.

| Decision | Options | Default if undecided |
|----------|---------|----------------------|
| **Hardware** | (a) Existing HoloPorts if they accept vanilla NixOS, (b) Intel NUCs, (c) RPi 5s, (d) BYO laptop | Verify (a) first. Fall back to BYO laptop. |
| **Fleet networking** | (a) Dedicated workshop router, (b) Sensorica lab wifi, (c) Mobile hotspot | Dedicated router, tested in advance. |
| **Deployment tooling** | colmena, deploy-rs, plain `nixos-rebuild` | colmena. Simpler than deploy-rs, scales to 5 nodes cleanly. |
| **Initial hApps** | Wind Tunnel, Moss, Vines, Requests & Offers | Wind Tunnel as primary (observable traffic for the Grafana moment), Moss as secondary (participants can join the group from their laptop client after the workshop). |
| **License** | CAL, AGPL, MIT | AGPL aligned with broader Holochain ecosystem, until OVN License direction is clarified. |
| **Repo home** | New repo under Sensorica org, fork to soushi888, or hAppenings Community org | Sensorica org with PR access from community contributors. |
| **Module observability** | Prometheus exporter, Grafana dashboards, plain logs | Prometheus + a minimal Grafana flake module. |

---

## 8. Migration from the archived repo

The archived [Sensorica/holoports-workshop](https://github.com/Sensorica/holoports-workshop) repo has 2 files:

* `holoport-workshop-guide.md`
* `workshop-notes-template.md`

Recommended migration:

1. **Do not unarchive.** The HolOS framing is dead weight. Archive serves as historical record of the December 2025 workshop.
2. **Pull the 2 markdown files** into `docs/archive/` of the new repo with a header note: *"Original HolOS based workshop, December 2025. Preserved for context. Current workshop uses NixOS, see workshop/facilitator-guide.md."*
3. **Reference the lessons** in the new facilitator guide. Specifically the workshop wifi pain point.
4. **Credit Marc and Jeff** in the README contributors section if they were involved.

---

## 9. Roadmap

**Phase 1: Module skeleton (2 to 3 weeks part time)**
- [ ] Repo initialized with flake skeleton
- [ ] `holochain-edgenode` module deploys a working conductor on one machine
- [ ] First hApp (Wind Tunnel) installs at boot
- [ ] CI on every push runs `nix flake check` and a NixOS VM test

**Phase 2: Workshop ready (3 to 4 weeks part time)**
- [ ] Fleet of 5 nodes deployable via `colmena apply`
- [ ] Workshop ISO that boots into a working dev environment
- [ ] Grafana module for observability
- [ ] Facilitator guide finalized
- [ ] Pre flight checklist sent to participants

**Phase 3: Community release**
- [ ] hAppenings Community Substack announcement
- [ ] hREA module (composable with edgenode module)
- [ ] HTTP Gateway module
- [ ] PAI module as optional layer
- [ ] Documentation site (mdBook or just rendered markdown)

**Phase 4: Production hardening**
- [ ] sops nix integration for secrets
- [ ] Lair keystore as separate service with proper lifecycle
- [ ] Backup and restore procedures
- [ ] Upgrade paths for Holochain version bumps
- [ ] Multi region fleet examples

---

## 10. How to contribute (placeholder for once the repo is live)

1. Open an issue describing what you want to add or change.
2. Fork, branch from `main`, submit PR.
3. CI must pass (`nix flake check`).
4. New modules need at least a NixOS VM test.
5. Documentation updates expected for any new public option.

---

## 11. Naming note

`holochain-nixos` is the working title. Alternatives to consider before going public:

* `holonix-edgenode` (clearer that it composes with Holonix)
* `holochain-modules` (more generic)
* `nixos-holochain` (mirrors `nixos-mailserver` and similar community conventions)
* `holo-fleet` (more evocative, less precise)

Recommended: **`nixos-holochain`** to match community naming conventions and signal "this is a NixOS thing for Holochain" rather than "this is a Holochain thing for NixOS." First impressions matter for adoption.

---

## Appendix A: Minimal `hosts/edgenode-01/configuration.nix`

```nix
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "edgenode-01";
  time.timeZone = "America/Montreal";

  services.openssh.enable = true;
  users.users.soushi = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
  };

  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;

  environment.systemPackages = with pkgs; [ git kate konsole firefox ];

  services.holochain-edgenode = {
    enable = true;
    openFirewall = true;
    happs = {
      windtunnel = {
        src = ../../happs/windtunnel.happ;
        networkSeed = "workshop-2026";
      };
      moss = {
        src = ../../happs/moss.happ;
        networkSeed = "sensorica-moss-2026";
      };
    };
  };

  system.stateVersion = "25.05";
}
```

## Appendix B: Quickstart for a participant

```bash
# Boot the workshop ISO or your own NixOS
sudo nixos-generate-config --root /mnt
git clone https://github.com/Sensorica/nixos-holochain
cd nixos-holochain
sudo nixos-install --flake .#edgenode-01

# Reboot, log in, verify
systemctl status holochain-conductor
journalctl -u holochain-conductor -f
```
