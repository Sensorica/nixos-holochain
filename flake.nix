{
  description = "Declarative NixOS modules for Holochain edgenodes and dev environments";

  # A flake input's own nixConfig is not applied transitively, so without this
  # every consumer (CI included) rebuilds Holochain from source instead of
  # pulling it from the Holochain Foundation's cache. CI already passes
  # `accept-flake-config = true`.
  nixConfig = {
    extra-substituters = ["https://holochain-ci.cachix.org"];
    extra-trusted-public-keys = [
      "holochain-ci.cachix.org-1:5IUSkZc0aoRS53rfkvH9Kid40NpyjwCMCzwRTXy+QN8="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    # Both supported Holochain lines, so the module's version switch is exercised
    # by real binaries rather than asserted (ADR-007 amended).
    holonix.url = "github:holochain/holonix/main-0.7";
    holonix-0_6.url = "github:holochain/holonix/main-0.6";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux"];

      flake = {
        # Reusable modules for downstream consumers.
        # The Sensorica fleet that exercises them lives in examples/sensorica-fleet.
        nixosModules = {
          holochain-edgenode = ./modules/holochain-edgenode.nix;
          holochain-windtunnel = ./modules/holochain-windtunnel.nix;
          holochain-http-gateway = ./modules/holochain-http-gateway.nix;
          holochain-grafana = ./modules/holochain-grafana.nix;
          pai = ./modules/pai.nix;
          default = ./modules;
        };

        # The one system in the root flake: a single edgenode with no hApp, so
        # anyone can run the module on a laptop with
        #   nixos-rebuild build-vm --flake .#minimal-vm && ./result/bin/run-*-vm
        # Fleets belong in their own flake; examples/sensorica-fleet is the worked one.
        nixosConfigurations.minimal-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            self.nixosModules.holochain-edgenode
            {
              _module.args.inputs = inputs;

              services.holochain-edgenode.enable = true;

              # Placeholders for the non-VM build; `build-vm` overrides both from
              # the qemu-vm module, so this configuration stays evaluable without
              # a hardware-configuration.nix.
              boot.loader.grub = {
                enable = true;
                device = "/dev/vda";
              };
              fileSystems."/" = {
                device = "/dev/disk/by-label/nixos";
                fsType = "ext4";
              };

              # Log in at the console without a password to read the unit status.
              services.getty.autologinUser = "root";
              users.users.root.initialHashedPassword = "";

              virtualisation.vmVariant.virtualisation = {
                memorySize = 4096;
                cores = 2;
                graphics = false;
              };

              system.stateVersion = "25.05";
            }
          ];
        };
      };

      perSystem = {
        pkgs,
        system,
        ...
      }: let
        holonix07 = inputs.holonix.packages.${system};
        holonix06 = inputs.holonix-0_6.packages.${system};

        # Bundles are fetched by hash and never committed (ADR-012).
        # Dino Adventure is the Foundation's own 0.7 demo app; Kando is the
        # 0.6-line equivalent. Hashes from `nix-prefetch-url`, cross-checked
        # against `sha256sum` of the resulting store path.
        dinoAdventureHapp = pkgs.fetchurl {
          url = "https://github.com/holochain/dino-adventure/releases/download/v0.3.0/dino-adventure-v0.3.0.happ";
          sha256 = "4dd11f7c5f5ee73f9472827e48ab3538f53f37f819af610bf8de95c10ee74f72";
        };
        kandoHapp = pkgs.fetchurl {
          url = "https://github.com/holochain-apps/kando/releases/download/v0.17.5/kando.happ";
          sha256 = "a4cdee64fe32720077e0aade94630f24d0da5e91da33ccbe5bfd894d9d359f28";
        };

        # A test node on either line. `hc` goes on the guest's PATH so the test
        # script drives the admin API exactly the way an operator would.
        edgenodeNode = {
          imports = [self.nixosModules.holochain-edgenode];
          _module.args.inputs = inputs;
        };

        hcOnPath = {config, ...}: {
          environment.systemPackages = [config.services.holochain-edgenode.hcPackage];
        };

        on06 = {
          services.holochain-edgenode = {
            package = holonix06.holochain;
            hcPackage = holonix06.hc;
          };
        };

        # 0.7 dispatches admin calls through `hc client call --port`; 0.6.3 has no
        # `client` subcommand at all and uses `hc sandbox call --running`.
        adminCall = {
          "0.7" = "hc client call --port 4444";
          "0.6" = "hc sandbox call --running 4444";
        };

        smokeTest = {
          name,
          line,
          nodeExtra ? {},
        }:
          pkgs.nixosTest {
            inherit name;
            nodes.machine = {
              imports = [edgenodeNode hcOnPath nodeExtra];
              services.holochain-edgenode.enable = true;
            };
            testScript = ''
              import re

              machine.wait_for_unit("holochain-conductor.service")
              machine.wait_for_open_port(4444)

              state = machine.succeed("systemctl is-active holochain-conductor.service").strip()
              assert state == "active", f"expected active, got {state}"

              # The admin interface answering list-apps is what "the port is open"
              # is supposed to mean; a listening socket alone would not prove it.
              apps = machine.succeed("${adminCall.${line}} list-apps").strip()
              assert apps == "[]", f"expected no apps on a bare node, got {apps}"

              journal = machine.succeed("journalctl -u holochain-conductor --no-pager")
              offenders = [
                  line
                  for line in journal.splitlines()
                  if re.search(r"(?i)error|panic|failed to parse", line)
              ]
              assert not offenders, "conductor journal is not clean:\n" + "\n".join(offenders)
            '';
          };

        happTest = {
          name,
          line,
          appId,
          happ,
          nodeExtra ? {},
        }:
          pkgs.nixosTest {
            inherit name;
            nodes.machine = {
              imports = [edgenodeNode hcOnPath nodeExtra];
              services.holochain-edgenode = {
                enable = true;
                appPort = 8888;
                happs.${appId} = {
                  src = happ;
                  networkSeed = "ci-test-seed";
                };
              };
            };
            testScript = ''
              # The bare app id also appears in the embedded manifest, so counting
              # installations means counting the installed_app_id key. Both lines
              # emit byte-identical JSON for these two.
              APP_KEY = '"installed_app_id":"${appId}"'
              ENABLED = '"status":{"type":"enabled"}'


              def assert_installed_once(stage):
                  machine.wait_for_unit("holochain-conductor.service")
                  machine.wait_for_unit("holochain-happ-installer.service")
                  machine.wait_for_open_port(8888)

                  result = machine.succeed(
                      "systemctl show -p Result --value holochain-happ-installer.service"
                  ).strip()
                  assert result == "success", f"[{stage}] installer Result={result}"

                  apps = machine.succeed("${adminCall.${line}} list-apps")
                  assert APP_KEY in apps, f"[{stage}] app id missing from list-apps: {apps}"
                  assert ENABLED in apps, f"[{stage}] app is not enabled: {apps}"

                  count = apps.count(APP_KEY)
                  assert count == 1, f"[{stage}] app listed {count} times, expected exactly 1"
                  machine.log(f"[{stage}] app is installed once and enabled")


              assert_installed_once("first boot")

              # A cold boot is the real test of both the idempotent installer and
              # the generated lair passphrase: neither may need a human.
              machine.shutdown()
              machine.start()

              assert_installed_once("after reboot")
            '';
          };
      in {
        packages = {
          holochain-0_6 = holonix06.holochain;
          hc-0_6 = holonix06.hc;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [nixos-rebuild colmena nil nixd alejandra];
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
                enable = true;
                scrapeTargets = ["127.0.0.1:9100"];
                openFirewall = true;
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

          vmTest = smokeTest {
            name = "holochain-edgenode-smoke";
            line = "0.7";
          };

          vmTest-0_6 = smokeTest {
            name = "holochain-edgenode-smoke-0_6";
            line = "0.6";
            nodeExtra = on06;
          };

          vmTestWithHapp = happTest {
            name = "holochain-edgenode-happ-installer";
            line = "0.7";
            appId = "dino-adventure";
            happ = dinoAdventureHapp;
          };

          vmTestWithHapp-0_6 = happTest {
            name = "holochain-edgenode-happ-installer-0_6";
            line = "0.6";
            appId = "kando";
            happ = kandoHapp;
            nodeExtra = on06;
          };
        };
      };
    };
}
