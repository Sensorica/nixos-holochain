# Sensorica Lab fleet: five Holochain edgenodes (sensorica-holoport-01 is the monitor
# node) plus the workshop live ISO. This is the worked example of what the
# nixos-holochain modules are for; copy it and edit hosts/ for your own fleet.
{
  description = "Sensorica Lab fleet of five Holochain edgenodes and the workshop ISO";

  inputs = {
    # The module repository's main branch, as any downstream fleet writes it.
    # A checkout of this repository overrides it with
    #   --override-input nixos-holochain <path-to-checkout>
    # (that is what CI and the review commands do).
    nixos-holochain.url = "github:Sensorica/nixos-holochain";
    # The fleet pins its own nixpkgs, as any downstream fleet does; the
    # Holochain toolchain comes from the module repository.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    holonix.follows = "nixos-holochain/holonix";
    # `nixosModules.sensorica-event-node` resolves its 0.6-line packages
    # through `inputs.holonix-0_6`, so any consumer of that module needs this
    # follow too (the same way `holonix` above is needed for
    # `holochain-edgenode`'s own default package).
    holonix-0_6.follows = "nixos-holochain/holonix-0_6";
    # The operator desk (hosts/desk.nix) declares the sensorica user's Plasma
    # session. Only this example needs them; the modules stay desktop-free.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixos-holochain,
    ...
  }: let
    system = "x86_64-linux";
    inherit (nixpkgs) lib;
    pkgs = import nixpkgs {inherit system;};

    hosts = ["sensorica-holoport-01" "sensorica-holoport-02" "sensorica-holoport-03" "sensorica-holoport-04" "sensorica-holoport-05"];

    # Passed to every host: the modules read inputs.holonix and
    # inputs.holonix-0_6 for their packages.
    specialArgs = {inherit inputs;};

    # ADR-015: this fleet runs the 0.6 line for September, from
    # `nixosModules.sensorica-event-node` (#33), which every host in
    # `fleetModules` below imports. Not a preference — every hApp the
    # workshop installs (hREA, Kando, Requests & Offers) has a 0.6 release
    # and none has a 0.7 one. The maintainers re-evaluate this seven days
    # before the workshop date.
    fleetModules = [
      nixos-holochain.nixosModules.holochain-edgenode
      nixos-holochain.nixosModules.holochain-grafana
      # Imported so hosts/common.nix can turn it off in writing rather than by
      # omission; see the comment there.
      nixos-holochain.nixosModules.holochain-windtunnel
      # The workshop event's package, hApps, seed, installer timeout and
      # metrics options — the same export any external host rehearsing the
      # event builds from. Both the nixosConfigurations and the colmena hive
      # get it, so a `colmena apply` and a `nixos-rebuild switch` install the
      # same bundles from the same conductor.
      nixos-holochain.nixosModules.sensorica-event-node
      # Off unless a host enables it; sensorica-holoport-01 hosts the
      # Sensorica Moss group's always-online node.
      nixos-holochain.nixosModules.holochain-moss-node
      # Off unless a host enables it; sensorica-holoport-01 runs the fleet's
      # Headscale and the public Grafana name until a second site takes them.
      nixos-holochain.nixosModules.admin-plane
      # What a person at the Holoport's own screen gets: launchers, a laid-out
      # Plasma session and the off-by-default event mode.
      inputs.home-manager.nixosModules.home-manager
      ./hosts/desk.nix
    ];

    mkEdgenode = name:
      lib.nixosSystem {
        inherit system specialArgs;
        modules = fleetModules ++ [./hosts/${name}/configuration.nix];
      };
  in {
    nixosConfigurations =
      lib.genAttrs hosts mkEdgenode
      // {
        # Bootable live ISO for workshop participants.
        workshop-iso = lib.nixosSystem {
          inherit system;
          modules = [./hosts/workshop-iso/configuration.nix];
        };
      };

    # Colmena hive: `colmena apply --on @all` from this directory.
    colmena =
      {
        meta = {
          nixpkgs = pkgs;
          inherit specialArgs;
        };
      }
      // lib.genAttrs hosts (name: {
        imports = fleetModules ++ [./hosts/${name}/configuration.nix];
      });

    devShells.${system}.default = pkgs.mkShell {
      buildInputs = with pkgs; [colmena nixos-rebuild alejandra];
    };

    checks.${system} = {
      # Guards #33: fails evaluation if sensorica-holoport-01's effective event-profile
      # values (package, hApp srcs, network seeds, installer timeout, the two
      # metrics enables) diverge from `nixosModules.sensorica-event-node`'s
      # own defaults, so a future override in this example that quietly
      # re-forks the profile is caught here instead of drifting unnoticed.
      #
      # `assertion` is forced while the derivation is constructed, which
      # happens during evaluation of `.drvPath` — so `nix flake check
      # --no-build` (what CI and the review commands run) catches a
      # divergence without building anything.
      eventProfileParity = let
        edge = self.nixosConfigurations.sensorica-holoport-01.config.services.holochain-edgenode;

        # The module's own defaults, evaluated the way any bare consumer
        # gets them: `holochain-edgenode` plus the profile, nothing else
        # layered on top. `_module.check = false` skips the rest of the
        # NixOS option set, the same way the root flake's own
        # `docs/module-options.md` generator does, since nothing here reads
        # `config` outside `services.holochain-edgenode`.
        moduleDefaults =
          (lib.evalModules {
            specialArgs = {inherit pkgs inputs;};
            modules = [
              {_module.check = false;}
              nixos-holochain.nixosModules.holochain-edgenode
              nixos-holochain.nixosModules.sensorica-event-node
            ];
          })
          .config
          .services
          .holochain-edgenode;

        # Fixed-output (fetchurl) and normally-built derivations both give a
        # deterministic store path for identical inputs, so `toString`
        # compares "the same content" without Nix trying (and failing) to
        # structurally compare two derivation attrsets.
        happShape = happs:
          lib.mapAttrs (_: h: {
            src = toString h.src;
            inherit (h) installed networkSeed;
          })
          happs;

        diffs = lib.filterAttrs (_: same: !same) {
          package = toString edge.package == toString moduleDefaults.package;
          hcPackage = toString edge.hcPackage == toString moduleDefaults.hcPackage;
          installerTimeout = edge.installerTimeout == moduleDefaults.installerTimeout;
          "metricsExporter.enable" = edge.metricsExporter.enable == moduleDefaults.metricsExporter.enable;
          "conductorMetrics.enable" = edge.conductorMetrics.enable == moduleDefaults.conductorMetrics.enable;
          happs = happShape edge.happs == happShape moduleDefaults.happs;
        };
      in
        pkgs.runCommand "sensorica-event-profile-parity" {
          assertion =
            if diffs == {}
            then "ok"
            else throw "sensorica-holoport-01 diverges from nixosModules.sensorica-event-node on: ${toString (builtins.attrNames diffs)}";
        } ''
          echo "$assertion" > $out
        '';
    };
  };
}
