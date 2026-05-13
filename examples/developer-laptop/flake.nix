# examples/developer-laptop — full dev env (Holonix + IDE + edgenode)
{
  description = "Full Holochain developer environment on NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    holonix.url = "github:holochain/holonix";
    nixos-holochain.url = "github:Sensorica/nixos-holochain";
  };

  outputs = { self, nixpkgs, holonix, nixos-holochain }: {
    nixosConfigurations.dev-laptop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-holochain.nixosModules.holochain-edgenode
        ({ pkgs, ... }: {
          services.holochain-edgenode = {
            enable = true;
            openFirewall = false; # local dev, no need to expose
          };

          # KDE Plasma 6 desktop for IDE workflow
          services.desktopManager.plasma6.enable = true;
          services.displayManager.sddm.enable = true;

          # Dev tooling
          environment.systemPackages = with pkgs; [
            git
            kate
            konsole
            firefox
            vscode
            nil      # Nix LSP
            nixd     # Alternative Nix LSP
            alejandra # Nix formatter
            # Holonix provides hc, holochain, lair-keystore
            holonix.packages.x86_64-linux.holonix
          ];

          networking.hostName = "holochain-dev";
          services.openssh.enable = true;
          system.stateVersion = "25.05";
        })
      ];
    };

    # Also expose a devShell for non-NixOS machines
    devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      buildInputs = [
        holonix.packages.x86_64-linux.holonix
      ];
    };
  };
}
