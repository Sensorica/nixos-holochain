# lib/default.nix — shared helper functions
{ lib, ... }:

{
  # mkEdgenode name — builds a standard nixosConfiguration for a fleet member.
  # Usage: inherit (import ./lib { inherit lib; }) mkEdgenode;
  mkEdgenode = name: nixpkgs: self: inputs:
    nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ../hosts/${name}/configuration.nix
        self.nixosModules.holochain-edgenode
      ];
      specialArgs = { inherit inputs; };
    };
}
