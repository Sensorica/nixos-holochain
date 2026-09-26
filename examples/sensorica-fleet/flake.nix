# Sensorica Lab fleet: five Holochain edgenodes (edgenode-01 is the monitor
# node) plus the workshop live ISO. This is the worked example of what the
# nixos-holochain modules are for; copy it and edit hosts/ for your own fleet.
{
  description = "Sensorica Lab fleet of five Holochain edgenodes and the workshop ISO";

  inputs = {
    # A checkout of this repository overrides it with
    #   --override-input nixos-holochain <path-to-checkout>
    # (that is what CI and the review commands do).
    nixos-holochain.url = "github:Sensorica/nixos-holochain";
    # The fleet pins its own nixpkgs, as any downstream fleet does; the
    # Holochain toolchain comes from the module repository.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    holonix.follows = "nixos-holochain/holonix";
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

    hosts = ["edgenode-01" "edgenode-02" "edgenode-03" "edgenode-04" "edgenode-05"];

    # Passed to every host: the module reads inputs.holonix for its packages.
    specialArgs = {inherit inputs;};

    # ADR-015: this fleet runs the 0.6 line for September. Not a preference —
    # every hApp the workshop installs (hREA, Kando, Requests & Offers) has a
    # 0.6 release and none has a 0.7 one. Both packages come from the module
    # repository's own outputs, so the fleet adds no input of its own and cannot
    # drift onto a different 0.6.3 than the one its VM tests ran against. The
    # principal re-evaluates this seven days before the workshop date.
    fleetLine = {
      holochain = nixos-holochain.packages.${system}.holochain-0_6;
      hc = nixos-holochain.packages.${system}.hc-0_6;
    };

    fleetHapps = import ./happs.nix {
      inherit pkgs;
      inherit (fleetLine) hc;
    };

    fleetModules = [
      nixos-holochain.nixosModules.holochain-edgenode
      nixos-holochain.nixosModules.holochain-grafana
      # Imported so hosts/common.nix can turn it off in writing rather than by
      # omission; see the comment there.
      nixos-holochain.nixosModules.holochain-windtunnel
      # Both the nixosConfigurations and the colmena hive get these, so a
      # `colmena apply` and a `nixos-rebuild switch` install the same bundles
      # from the same conductor.
      {_module.args = {inherit fleetLine fleetHapps;};}
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
  };
}
