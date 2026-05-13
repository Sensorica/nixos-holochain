# examples/minimal — just a conductor, no extras
{
  description = "Minimal nixos-holochain example — conductor only";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-holochain.url = "github:Sensorica/nixos-holochain";
  };

  outputs = { self, nixpkgs, nixos-holochain }: {
    nixosConfigurations.my-node = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-holochain.nixosModules.holochain-edgenode
        ({ ... }: {
          services.holochain-edgenode = {
            enable = true;
            openFirewall = true;
          };
          # Minimal system config
          networking.hostName = "my-holochain-node";
          services.openssh.enable = true;
          system.stateVersion = "25.05";
        })
      ];
    };
  };
}
