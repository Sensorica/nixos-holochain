# examples/moss-group — edgenode hosting a Moss group
{
  description = "Edgenode hosting a Moss group via nixos-holochain";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-holochain.url = "github:Sensorica/nixos-holochain";
  };

  outputs = { self, nixpkgs, nixos-holochain }: {
    nixosConfigurations.moss-node = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-holochain.nixosModules.holochain-edgenode
        ({ ... }: {
          services.holochain-edgenode = {
            enable = true;
            openFirewall = true;
            happs = {
              moss = {
                # Fetch moss.happ and place it here, or reference a flake input
                src = ./moss.happ;
                networkSeed = "my-group-2026";
              };
            };
          };
          networking.hostName = "moss-group-node";
          services.openssh.enable = true;
          system.stateVersion = "25.05";
        })
      ];
    };
  };
}
