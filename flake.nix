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

      flake = let
        # Everything the two demo VMs share: no bootloader or filesystem worth
        # the name (`build-vm` overrides both from the qemu-vm module), a
        # console you can read without a password, and room for a conductor.
        vmBase = {
          _module.args.inputs = inputs;

          boot.loader.grub = {
            enable = true;
            device = "/dev/vda";
          };
          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };

          services.getty.autologinUser = "root";
          users.users.root.initialHashedPassword = "";

          system.stateVersion = "25.05";
        };
      in {
        # `nix flake init -t github:Sensorica/nixos-holochain#minimal` (or
        # `#fleet`) is the whole adoption story, so the templates point at the
        # published flake rather than a relative path: a copied tree has to
        # build from anywhere, not only from inside a checkout. The template
        # checks override the input to test the working tree.
        templates = rec {
          minimal = {
            path = ./templates/minimal;
            description = "A single Holochain edgenode: conductor, lair, hApp installer";
            welcomeText = ''
              # A Holochain edgenode

              - Paste your SSH public key into `configuration.nix`.
              - Replace `hardware-configuration.nix` with
                `nixos-generate-config --show-hardware-config` from the target machine.
              - `nix flake check --no-build`, then
                `sudo nixos-rebuild switch --flake .#edgenode`.

              README.md has the rest.
            '';
          };

          fleet = {
            path = ./templates/fleet;
            description = "Five Holochain edgenodes with Grafana on node-01, a colmena hive and a live ISO";
            welcomeText = ''
              # A Holochain edgenode fleet

              - Rename `hosts/node-0*` and the `hosts` list in `flake.nix` to your machines.
              - Paste your SSH public key into `hosts/common.nix`.
              - Replace each `hardware-configuration.nix` with real output from that machine.
              - `nix flake check --no-build`, then `nix develop` and
                `colmena apply --impure --on @all`.

              README.md has the rest.
            '';
          };

          default = minimal;
        };

        # Reusable modules for downstream consumers.
        # The Sensorica fleet that exercises them lives in examples/sensorica-fleet.
        nixosModules = {
          holochain-edgenode = ./modules/holochain-edgenode.nix;
          holochain-windtunnel = ./modules/holochain-windtunnel.nix;
          holochain-http-gateway = ./modules/holochain-http-gateway.nix;
          holochain-grafana = ./modules/holochain-grafana.nix;
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
            vmBase
            {
              services.holochain-edgenode.enable = true;

              virtualisation.vmVariant.virtualisation = {
                memorySize = 4096;
                cores = 2;
                graphics = false;
              };
            }
          ];
        };

        # The observability stack on one machine, for looking at the dashboard
        # before deploying a fleet:
        #   nixos-rebuild build-vm --flake .#observability-vm
        #   ./result/bin/run-observability-vm-vm
        # then http://localhost:13000 (admin / workshop2026). Grafana and
        # Prometheus are forwarded to the host so a real browser can reach
        # them; nothing else is.
        nixosConfigurations.observability-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            self.nixosModules.holochain-edgenode
            self.nixosModules.holochain-grafana
            vmBase
            {
              networking.hostName = "observability-vm";

              services.holochain-edgenode = {
                enable = true;
                metricsExporter.enable = true;
                conductorMetrics.enable = true;
                # A short interval so a demo VM fills its panels while someone
                # is still watching. A real fleet leaves this at 30s.
                conductorMetrics.interval = "10s";
              };

              services.holochain-grafana = {
                enable = true;
                scrapeTargets = ["127.0.0.1:9100"];
                # Without this the forwarded ports connect and then hang: the
                # NixOS firewall drops them inside the guest.
                openFirewall = true;
              };

              virtualisation.vmVariant.virtualisation = {
                memorySize = 4096;
                cores = 4;
                graphics = false;
                forwardPorts = [
                  {
                    from = "host";
                    host.port = 13000;
                    guest.port = 3000;
                  }
                  {
                    from = "host";
                    host.port = 19090;
                    guest.port = 9090;
                  }
                ];
              };
            }
          ];
        };
      };

      perSystem = {
        pkgs,
        system,
        ...
      }: let
        holonix06 = inputs.holonix-0_6.packages.${system};

        # The gateway is a Rust crate on the 2024 edition whose toolchain file
        # asks for a rustc newer than nixos-25.05 carries, so it is built
        # against the nixpkgs each holonix line already pins rather than
        # against ours. That keeps the conductor and its gateway on one
        # toolchain and adds no input to the lock.
        gatewayPkgs = inputs.holonix.inputs.nixpkgs.legacyPackages.${system};
        gatewayPkgs06 = inputs.holonix-0_6.inputs.nixpkgs.legacyPackages.${system};

        # ---- generated option reference ------------------------------------
        #
        # docs/module-options.md was hand-written and had already drifted from
        # the modules twice, so it is generated from the declarations instead
        # and CI diffs the committed file against a fresh build.
        #
        # `evalModules` rather than a whole NixOS system: the four modules
        # declare the options, and nothing here reads `config`, so the NixOS
        # module set is not needed and the document contains our options only.
        optionsEval = pkgs.lib.evalModules {
          specialArgs = {inherit pkgs inputs;};
          modules = [
            # The modules define NixOS options (systemd units, firewall,
            # assertions) that only a full NixOS evaluation declares. None of
            # them is read here, so the definitions are left unchecked rather
            # than dragging in the whole NixOS module set to document four
            # files' worth of options.
            {_module.check = false;}
            ./modules/holochain-edgenode.nix
            ./modules/holochain-grafana.nix
            ./modules/holochain-windtunnel.nix
            ./modules/holochain-http-gateway.nix
          ];
        };

        optionsDoc = pkgs.nixosOptionsDoc {
          # `_module` is the module system's own plumbing, which NixOS hides
          # and a bare `evalModules` does not.
          options = builtins.removeAttrs optionsEval.options ["_module"];

          # Declarations come out as absolute store paths, and the store hash
          # changes with every commit; left alone the document would differ
          # from itself on any change at all and the drift check would be
          # noise. Rewritten to repository-relative links instead.
          transformOptions = opt:
            opt
            // {
              declarations =
                map (
                  decl: let
                    path = pkgs.lib.removePrefix (toString ./. + "/") (toString decl);
                  in {
                    name = path;
                    url = "https://github.com/Sensorica/nixos-holochain/blob/main/${path}";
                  }
                )
                opt.declarations;
            };
        };

        optionsDocHeader = pkgs.writeText "module-options-header.md" ''
          # Module options

          Generated from the module declarations by `nix build .#options-doc`; do not edit by hand. CI fails when this file differs from a fresh build, so regenerate it in the same commit as any option change:

          ```bash
          cp "$(nix build .#options-doc --print-out-paths)" docs/module-options.md
          ```

          The prose about how the modules fit together lives in [`architecture.md`](architecture.md).

        '';

        # Bundles are fetched by hash and never committed (ADR-012).

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

        # The test driver's default node is a single core with 1G of RAM, on
        # which the conductor needs five minutes to come up and compiling an
        # app's wasm outruns the admin client's request deadline.
        roomToWork = {
          virtualisation = {
            cores = 4;
            memorySize = 4096;
            diskSize = 8192;
          };
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
              imports = [edgenodeNode hcOnPath roomToWork nodeExtra];
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

        # The conductor gauges have to exist on both lines, and the only thing
        # that differs between them is the admin call prefix. So this runs the
        # module's own timer against a real conductor of each line rather than
        # asserting that the prefix is right.
        metricsTest = {
          name,
          nodeExtra ? {},
        }:
          pkgs.nixosTest {
            inherit name;
            nodes.machine = {
              imports = [edgenodeNode roomToWork nodeExtra];
              services.holochain-edgenode = {
                enable = true;
                metricsExporter.enable = true;
                conductorMetrics.enable = true;
              };
            };
            testScript = ''
              machine.wait_for_unit("holochain-conductor.service")
              machine.wait_for_unit("prometheus-node-exporter.service")
              machine.wait_for_unit("holochain-conductor-metrics.timer")

              machine.wait_until_succeeds(
                  "curl -s localhost:9100/metrics | grep '^holochain_conductor_up 1'",
                  timeout=180,
              )
              series = machine.succeed("curl -s localhost:9100/metrics | grep '^holochain_'")
              machine.log("holochain series on /metrics:\n" + series)

              for name in [
                  "holochain_conductor_up",
                  "holochain_conductor_peer_connections",
                  "holochain_conductor_direct_peer_connections",
                  "holochain_conductor_peer_urls",
                  "holochain_conductor_network_sent_bytes_total",
                  "holochain_conductor_network_received_bytes_total",
                  "holochain_conductor_network_sent_messages_total",
                  "holochain_conductor_network_received_messages_total",
                  "holochain_conductor_blocked_messages_total",
                  "holochain_conductor_metrics_scrape_timestamp_seconds",
              ]:
                  assert name in series, f"{name} missing:\n{series}"
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
              imports = [edgenodeNode hcOnPath roomToWork nodeExtra];
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

          # One gateway build per Holochain line, so an operator can check
          # which binary a node would run without evaluating a whole system.
          # The module picks between them from the conductor's version.
          holochain-http-gateway = gatewayPkgs.callPackage ./packages/holochain-http-gateway.nix {line = "0.7";};
          holochain-http-gateway-0_6 = gatewayPkgs06.callPackage ./packages/holochain-http-gateway.nix {line = "0.6";};

          # The committed docs/module-options.md is a copy of this build.
          options-doc = pkgs.runCommand "module-options.md" {} ''
            cat ${optionsDocHeader} ${optionsDoc.optionsCommonMark} > $out
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [nixos-rebuild colmena nil nixd alejandra];
        };

        checks = {
          # One node wearing both roles: an edgenode exporting its conductor's
          # own stats, and the monitor scraping and drawing them. That is the
          # whole observability path in a single VM, so a break anywhere in it
          # fails here rather than at the workshop.
          vmTestGrafana = pkgs.nixosTest {
            name = "holochain-grafana-smoke";
            nodes.machine = {
              imports = [
                edgenodeNode
                roomToWork
                self.nixosModules.holochain-grafana
              ];
              environment.systemPackages = [pkgs.jq];
              services.holochain-edgenode = {
                enable = true;
                metricsExporter.enable = true;
                conductorMetrics.enable = true;
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

              # ---- criterion 4: the conductor's own series ----
              machine.wait_for_unit("holochain-conductor.service")
              machine.wait_for_unit("holochain-conductor-metrics.timer")

              # The timer fires on its interval; the first file may not exist
              # yet when the conductor has only just come up.
              machine.wait_until_succeeds(
                  "curl -s localhost:9100/metrics | grep '^holochain_'", timeout=180
              )
              holochain_metrics = machine.succeed(
                  "curl -s localhost:9100/metrics | grep '^holochain_'"
              )
              machine.log("holochain series on /metrics:\n" + holochain_metrics)
              assert "holochain_conductor_up 1" in holochain_metrics, (
                  "the conductor answered dump-network-stats nowhere:\n" + holochain_metrics
              )

              # ---- criterion 3: every configured target is up ----
              machine.wait_until_succeeds(
                  "curl -s localhost:9090/api/v1/targets"
                  " | jq -e '.data.activeTargets | length > 0"
                  " and all(.[]; .health == \"up\")'",
                  timeout=120,
              )
              targets = machine.succeed(
                  "curl -s localhost:9090/api/v1/targets"
                  " | jq -c '.data.activeTargets[] | {scrapeUrl, health, lastError}'"
              )
              machine.log("prometheus targets:\n" + targets)
              assert '"health":"up"' in targets, targets
              assert '"health":"down"' not in targets, targets

              # Prometheus has to have kept the conductor series, not merely
              # scraped it once: this is what the dashboard actually queries.
              # The target goes "up" on its first scrape, which can land before
              # the metrics timer has written its first textfile, so this waits
              # for a scrape that carries the series rather than asserting once.
              machine.wait_until_succeeds(
                  "curl -s --get localhost:9090/api/v1/query"
                  " --data-urlencode 'query=holochain_conductor_up'"
                  " | jq -e '.data.result | length > 0'",
                  timeout=180,
              )
              series = machine.succeed(
                  "curl -s --get localhost:9090/api/v1/query"
                  " --data-urlencode 'query=holochain_conductor_up'"
                  " | jq -c '.data.result'"
              )
              machine.log("holochain_conductor_up in prometheus: " + series)
              assert '"__name__":"holochain_conductor_up"' in series, series

              # ---- criterion 5: the dashboard is provisioned ----
              search = machine.succeed(
                  "curl -s -u admin:workshop2026"
                  " 'http://localhost:3000/api/search?query=Holochain'"
              )
              machine.log("grafana search: " + search)
              assert '"title":"Holochain Fleet"' in search, search
              assert '"uid":"holochain-fleet"' in search, search

              # A provisioned dashboard that Grafana cannot bind to a data
              # source renders empty panels, which a search hit would not show.
              datasource = machine.succeed(
                  "curl -s -u admin:workshop2026"
                  " http://localhost:3000/api/datasources/uid/holochain-prometheus"
              )
              machine.log("grafana datasource: " + datasource)
              assert '"type":"prometheus"' in datasource, datasource
            '';
          };

          # The test sandbox has no network, so this asserts what the module
          # generates rather than a running container; the image is pulled and
          # run for real on the Builder's machine (see the PR body).
          vmTestWindtunnel = pkgs.nixosTest {
            name = "holochain-windtunnel-unit";
            nodes.machine = {
              imports = [self.nixosModules.holochain-windtunnel];
              services.holochain-windtunnel = {
                enable = true;
                # No registry is reachable from the sandbox, so the unit is
                # generated but never started.
                autoStart = false;
              };
              networking.hostName = "edgenode-42";
              virtualisation.diskSize = 4096;
            };
            testScript = ''
              import re

              machine.wait_for_unit("multi-user.target")

              # The backend has to be there for the unit to mean anything.
              machine.succeed("podman --version")
              machine.succeed("podman ps")

              unit = machine.succeed("systemctl cat podman-wind-tunnel-runner.service")
              machine.log("unit:\n" + unit)

              exec_start = re.search(r"ExecStart=(\S+)", unit)
              assert exec_start is not None, "no ExecStart in the unit:\n" + unit
              run = machine.succeed(f"cat {exec_start.group(1)}")
              machine.log("generated run script:\n" + run)

              for flag in ["--net=host", "--privileged", "--cgroupns=host"]:
                  assert flag in run, f"{flag} missing from the generated run command:\n{run}"

              assert "--hostname=nomad-client-edgenode-42" in run, run
              assert (
                  "ghcr.io/holochain/wind-tunnel-runner@sha256:"
                  "650c91806275681bc1961e0e55e85fa7fbf31bebe0c8665fc0a6af71ac330fa2"
              ) in run, run

              # `--pull missing` is the pull command the unit runs: podman
              # fetches the digest on first start and never again.
              assert "--pull missing" in run, run

              # autoStart = false has to mean exactly that, or a fleet would
              # start donating compute the moment the module is imported.
              enabled = machine.succeed(
                  "systemctl is-enabled podman-wind-tunnel-runner.service || true"
              ).strip()
              machine.log(f"is-enabled: {enabled}")
              assert enabled != "enabled", enabled
              assert "wind-tunnel-runner" not in machine.succeed("podman ps")
            '';
          };

          # A real zome call through the gateway, on a node that installed a
          # real hApp. The allow list names exactly one read function, so the
          # 200 proves the whole path (conductor -> admin API -> app websocket
          # -> zome -> JSON) and the 403 proves the allow list is what decides,
          # not the absence of a route: `get_all_dinos` exists, takes the same
          # (empty) payload and lives in the same zome as the allowed
          # `get_all_dinos_local`.
          vmTestGateway = pkgs.nixosTest {
            name = "holochain-http-gateway";
            nodes.machine = {
              imports = [
                edgenodeNode
                hcOnPath
                roomToWork
                self.nixosModules.holochain-http-gateway
              ];
              environment.systemPackages = [pkgs.jq];

              services.holochain-edgenode = {
                enable = true;
                appPort = 8888;
                happs.dino-adventure = {
                  src = dinoAdventureHapp;
                  networkSeed = "ci-gateway-seed";
                };
              };

              services.holochain-http-gateway = {
                enable = true;
                allowedAppIds = ["dino-adventure"];
                allowedFns.dino-adventure = ["dino_adventure/get_all_dinos_local"];
              };
            };
            testScript = ''
              import re

              machine.wait_for_unit("holochain-conductor.service")
              machine.wait_for_unit("holochain-happ-installer.service")
              machine.wait_for_unit("holochain-http-gateway.service")
              machine.wait_for_open_port(8090)

              state = machine.succeed(
                  "systemctl is-active holochain-http-gateway.service"
              ).strip()
              assert state == "active", f"expected active, got {state}"

              # /health is the only path that works with nothing allowed, so it
              # separates "the gateway is up" from "the call was authorised".
              health = machine.succeed("curl -sf http://127.0.0.1:8090/health").strip()
              machine.log("health: " + health)

              # The gateway addresses a cell by DNA hash, which is only known
              # once the app is installed. Every holo_hash is multibase 'u' plus
              # a three-byte type prefix, and DnaHash's is hC0k, so this picks
              # the DNA hash out of list-apps without depending on the shape of
              # its JSON (which differs between lines).
              apps = machine.succeed("hc client call --port 4444 list-apps")
              machine.log("list-apps:\n" + apps)
              dna_hashes = sorted(set(re.findall(r"uhC0k[A-Za-z0-9_-]+", apps)))
              assert len(dna_hashes) == 1, f"expected one DNA hash, got {dna_hashes}"
              dna = dna_hashes[0]
              machine.log("dna hash: " + dna)

              # base64url of the JSON document `null`, which the gateway
              # transcodes to msgpack nil: the payload a zero-argument zome
              # function takes.
              PAYLOAD = "bnVsbA%3D%3D"

              def call(fn):
                  url = (
                      f"http://127.0.0.1:8090/{dna}/dino-adventure"
                      f"/dino_adventure/{fn}?payload={PAYLOAD}"
                  )
                  code = machine.succeed(
                      f"curl -s -o /tmp/body -w '%{{http_code}}' '{url}'"
                  ).strip()
                  body = machine.succeed("cat /tmp/body")
                  machine.log(f"GET {fn} -> {code} {body}")
                  return code, body

              # ---- the allowed read function answers 200 with JSON ----
              code, body = call("get_all_dinos_local")
              assert code == "200", f"allowed function answered {code}: {body}"
              machine.succeed("jq -e . /tmp/body >/dev/null")
              assert body.strip() == "[]", f"expected an empty dino list, got {body}"

              # ---- a function outside the allow list answers 403 ----
              code, body = call("get_all_dinos")
              assert code == "403", f"unallowed function answered {code}: {body}"
              machine.succeed("jq -e .error /tmp/body >/dev/null")
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

          # The 0.7 line's gauges are covered end to end by vmTestGrafana; this
          # is the 0.6 half of "both lines produce it".
          vmTestConductorMetrics-0_6 = metricsTest {
            name = "holochain-conductor-metrics-0_6";
            nodeExtra = on06;
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
