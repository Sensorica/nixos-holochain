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

    fleetModules = [
      nixos-holochain.nixosModules.holochain-edgenode
      nixos-holochain.nixosModules.holochain-grafana
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
