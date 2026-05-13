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
          holochain-edgenode   = ./modules/holochain-edgenode.nix;
          holochain-windtunnel = ./modules/holochain-windtunnel.nix;
          holochain-http-gateway = ./modules/holochain-http-gateway.nix;
          holochain-grafana    = ./modules/holochain-grafana.nix;
          pai                  = ./modules/pai.nix;
          default              = ./modules;
        };

        # Concrete fleet of 5 workshop nodes
        nixosConfigurations =
          let
            mkEdgenode = name: nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./hosts/${name}/configuration.nix
                self.nixosModules.holochain-edgenode
              ];
              specialArgs = { inherit inputs; };
            };
          in
          {
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

        checks = {
          vmTestGrafana = pkgs.nixosTest {
            name = "holochain-grafana-smoke";
            nodes.machine = {
              imports = [
                self.nixosModules.holochain-edgenode
                self.nixosModules.holochain-grafana
              ];
              _module.args.inputs = inputs;
              services.holochain-edgenode = {
                enable = true;
                metricsExporter.enable = true;
              };
              services.holochain-grafana = {
                enable        = true;
                scrapeTargets = [ "127.0.0.1:9100" ];
                openFirewall  = true;
              };
            };
            testScript = ''
              machine.wait_for_unit("grafana.service")
              machine.wait_for_unit("prometheus.service")
              machine.wait_for_open_port(3000)
              machine.wait_for_open_port(9090)
              machine.succeed("curl -sf http://localhost:3000/api/health")
            '';
          };

          vmTest = pkgs.nixosTest {
            name = "holochain-edgenode-smoke";
            nodes.machine = {
              imports = [ self.nixosModules.holochain-edgenode ];
              _module.args.inputs = inputs;
              services.holochain-edgenode.enable = true;
            };
            testScript = ''
              machine.wait_for_unit("holochain-conductor.service")
              machine.wait_for_open_port(4444)
              output = machine.succeed("systemctl is-active holochain-conductor.service")
              assert output.strip() == "active", f"Expected active, got: {output}"
              machine.log("Conductor is up and accepting connections on :4444")
            '';
          };
        } // pkgs.lib.optionalAttrs (builtins.pathExists ./happs/windtunnel.happ) {
          vmTestWithHapp = pkgs.nixosTest {
            name = "holochain-edgenode-happ-installer";
            nodes.machine = {
              imports = [ self.nixosModules.holochain-edgenode ];
              _module.args.inputs = inputs;
              services.holochain-edgenode = {
                enable  = true;
                appPort = 8888;
                happs.windtunnel = {
                  src         = ./happs/windtunnel.happ;
                  networkSeed = "ci-test-seed";
                };
              };
            };
            testScript = ''
              machine.wait_for_unit("holochain-conductor.service")
              machine.wait_for_unit("holochain-happ-installer.service")
              machine.wait_for_open_port(8888)
              machine.succeed("systemctl is-active holochain-happ-installer.service")
            '';
          };
        };
      };
    };
}
