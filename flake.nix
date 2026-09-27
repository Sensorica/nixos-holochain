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
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
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

          system.stateVersion = "26.05";
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
        nixosModules = let
          # The bootstrap server's package comes from this flake rather than
          # from the consumer's `inputs`, which need not carry a holonix 0.6
          # input at all. The module file itself declares no default, so this
          # wrapper is what fills it.
          bootstrapPackage = {
            lib,
            pkgs,
            ...
          }: {
            services.holochain-bootstrap.package =
              lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.bootstrap-srv-0_6;
          };
        in {
          holochain-edgenode = ./modules/holochain-edgenode.nix;
          holochain-windtunnel = ./modules/holochain-windtunnel.nix;
          holochain-http-gateway = ./modules/holochain-http-gateway.nix;
          holochain-grafana = ./modules/holochain-grafana.nix;
          holochain-bootstrap = {
            imports = [./modules/holochain-bootstrap.nix bootstrapPackage];
          };
          default = {
            imports = [./modules bootstrapPackage];
          };
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

        # The gateway is a Rust crate on the 2024 edition, built against the
        # nixpkgs each holonix line already pins rather than against ours
        # (first because nixos-25.05's rustc was too old for its toolchain
        # file). That keeps the conductor and its gateway on one
        # toolchain and adds no input to the lock.
        gatewayPkgs = inputs.holonix.inputs.nixpkgs.legacyPackages.${system};
        gatewayPkgs06 = inputs.holonix-0_6.inputs.nixpkgs.legacyPackages.${system};

        # The textfile exporter every conductor on a machine runs; the edgenode
        # module builds its own with its `hc`.
        conductorExporter = pkgs.callPackage ./packages/holochain-conductor-exporter.nix {
          hc = inputs.holonix.packages.${system}.hc;
        };
        # The jq programs as the exporter runs them, with families.jq beside
        # them for `jq -L`.
        inherit (conductorExporter) jqLib;
        metricsChecks = import ./tests/metrics.nix {
          inherit pkgs;
          exporter = conductorExporter;
        };

        # A monitor node's evaluated config, for the checks that read what the
        # grafana module renders without booting anything.
        monitor = extra:
          (inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules =
              [
                self.nixosModules.holochain-grafana
                {
                  networking.hostName = "monitor";
                  system.stateVersion = "26.05";
                  services.holochain-grafana.enable = true;
                }
              ]
              ++ extra;
          }).config;
        # The recording rules as the module renders them with its defaults.
        holochainRulesFile = builtins.head (monitor []).services.prometheus.ruleFiles;
        # Two conductors' textfiles at the capture's clock, for the rule tests
        # and vmTestGrafana.
        fixtureTextfiles = import ./tests/fixture-textfiles.nix {
          inherit pkgs jqLib;
          inherit (metricsChecks) names;
        };

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
            # than dragging in the whole NixOS module set to document five
            # files' worth of options.
            {_module.check = false;}
            ./modules/holochain-edgenode.nix
            ./modules/holochain-grafana.nix
            ./modules/holochain-windtunnel.nix
            ./modules/holochain-http-gateway.nix
            ./modules/holochain-bootstrap.nix
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

        # The Grafana test authenticates against the API, so it needs the
        # password its node runs with. It sets its own rather than leaning on
        # the module default, so no credential pair sits next to a curl
        # invocation in this file.
        grafanaTestPassword = "vmtest";

        # A scrape target vmTestGrafana names and nothing listens on.
        deadTarget = "127.0.0.1:9999";

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
          pkgs.testers.nixosTest {
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
          pkgs.testers.nixosTest {
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
                  "curl -s localhost:9100/metrics | grep -F 'holochain_conductor_up{conductor=\"Holochain\"} 1'",
                  timeout=180,
              )
              series = machine.succeed("curl -s localhost:9100/metrics | grep '^holochain_'")
              machine.log("holochain series on /metrics:\n" + series)

              # Every sample names its conductor, "Holochain" while
              # conductorMetrics.name is left at its default.
              for line in series.splitlines():
                  assert 'conductor="Holochain"' in line, f"no conductor label: {line}"

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

              # list-apps answered on this line too, with no app installed; an
              # unanswered call would leave the line out rather than write 0.
              assert 'holochain_conductor_apps{conductor="Holochain",status="enabled"} 0' in series, series
            '';
          };

        happTest = {
          name,
          line,
          appId,
          happ,
          nodeExtra ? {},
        }:
          pkgs.testers.nixosTest {
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
                # The per-DHT series need an installed app to have a DHT at
                # all, so they are asserted here rather than in metricsTest.
                metricsExporter.enable = true;
                conductorMetrics.enable = true;
              };
            };
            testScript = ''
              import json
              import re

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

              # ---- one per-DHT series set for every cell of the app ----
              # The cells the conductor itself reports, not a list written here.
              apps = json.loads(machine.succeed("${adminCall.${line}} list-apps"))
              cells = [
                  (role, cell["value"]["cell_id"]["dna_hash"])
                  for app in apps
                  if app["installed_app_id"] == "${appId}"
                  for role, infos in app["cell_info"].items()
                  for cell in infos
                  if "cell_id" in cell.get("value", {})
              ]
              machine.log(f"cells of ${appId}: {cells}")
              assert cells, f"no cell with a DNA hash in list-apps: {apps}"

              machine.wait_for_unit("prometheus-node-exporter.service")
              machine.wait_until_succeeds(
                  "curl -s localhost:9100/metrics"
                  " | grep '^holochain_dht_peers{' | grep -F 'app_id=\"${appId}\"'",
                  timeout=180,
              )
              series = machine.succeed("curl -s localhost:9100/metrics | grep '^holochain_'")
              machine.log("holochain series on /metrics:\n" + series)

              # The conductor series are still there next to them.
              assert 'holochain_conductor_up{conductor="Holochain"} 1' in series, series
              assert 'holochain_conductor_apps{conductor="Holochain",status="enabled"} 1' in series, series

              # node_exporter re-sorts labels, so a series is keyed by its
              # name and its label set rather than by the line's spelling.
              values = {}
              rows = []
              for line in series.splitlines():
                  m = re.fullmatch(r'(\w+)(?:\{(.*)\})? (\S+)', line)
                  assert m, f"unparsable line: {line}"
                  labels = frozenset(re.findall(r'(\w+)="([^"]*)"', m.group(2) or ""))
                  values[m.group(1) + str(sorted(labels))] = m.group(3)
                  rows.append((m.group(1), dict(labels), m.group(3)))

              # The app is named once, enabled, by a name that is not its id's hash.
              app_info = [
                  r for r in rows
                  if r[0] == "holochain_app_info" and r[1].get("app_id") == "${appId}"
              ]
              assert len(app_info) == 1, f"holochain_app_info for ${appId}: {app_info}"
              assert app_info[0][1]["status"] == "enabled", app_info
              assert app_info[0][1]["conductor"] == "Holochain", app_info
              assert app_info[0][1]["app_name"] != "", app_info

              for role, dna in cells:
                  key = {("conductor", "Holochain"), ("app_id", "${appId}"), ("role", role), ("dna", dna)}
                  labels = str(sorted(key))
                  # One name row per DHT, keyed like its data series, whose
                  # names carry no hash and no Moss escape.
                  info = [
                      r for r in rows
                      if r[0] == "holochain_dht_info" and key <= set(r[1].items())
                  ]
                  assert len(info) == 1, f"{len(info)} holochain_dht_info rows for {key}:\n{series}"
                  for label in ["app_name", "app_kind", "part_name", "network_label"]:
                      value = info[0][1][label]
                      assert "uhC" not in value and "$" not in value, f"{label}={value!r}"
                  assert info[0][1]["network_label"] != "", info
                  for name in [
                      "holochain_dht_peers",
                      "holochain_dht_local_ops",
                      "holochain_dht_peer_ops",
                      "holochain_dht_pending_fetches",
                      "holochain_dht_seconds_since_gossip",
                      "holochain_dht_completed_rounds_total",
                      "holochain_dht_peer_timeouts_total",
                  ]:
                      assert name + labels in values, f"{name}{labels} missing:\n{series}"
                  # A node alone on its network has no peer and has never
                  # gossiped: 0 peers and -1, not an age since the epoch.
                  assert values["holochain_dht_peers" + labels] == "0", values
                  assert values["holochain_dht_seconds_since_gossip" + labels] == "-1", values
            '';
          };

        # Two 0.6 edgenodes and a holochain-bootstrap server on a network with
        # no way out: the only place alice and bob can learn about each other,
        # and the only relay they can get a peer URL from, is `bootstrap`.
        # The pass condition is that each conductor holds the other's agent
        # info for Kando's DNA, with a peer URL on that relay.
        #
        # `bobBootstrapPort` exists for the falsifier: pointed at a port
        # nothing listens on, bob never registers and the same assertion has
        # to fail (legacyPackages.falsifiers). Relay and bootstrap are both
        # plain HTTP, which is what relayAllowPlainText is for.
        bootstrapTest = {
          name,
          bobBootstrapPort ? 443,
        }:
          pkgs.testers.nixosTest {
            inherit name;
            nodes = let
              edgenode = port: {
                imports = [edgenodeNode hcOnPath on06];
                virtualisation = {
                  cores = 2;
                  memorySize = 2048;
                  diskSize = 4096;
                };
                services.holochain-edgenode = {
                  enable = true;
                  bootstrapUrl = "http://bootstrap:${toString port}";
                  relayUrl = "http://bootstrap:443/relay";
                  relayAllowPlainText = true;
                  # The conductor default, set so the rendered key is proven
                  # accepted by a real 0.6 conductor without changing behaviour.
                  requestTimeoutS = 60;
                  happs.kando = {
                    src = kandoHapp;
                    networkSeed = "ci-bootstrap-seed";
                  };
                };
              };
            in {
              bootstrap = {
                imports = [self.nixosModules.holochain-bootstrap];
                services.holochain-bootstrap = {
                  enable = true;
                  openFirewall = true;
                };
                environment.systemPackages = [pkgs.procps];
              };
              alice = edgenode 443;
              bob = edgenode bobBootstrapPort;
            };
            testScript = ''
              import json
              import re
              import time

              CALL = "${adminCall."0.6"}"


              def cpu_ns():
                  return int(bootstrap.succeed(
                      "systemctl show -p CPUUsageNSec --value holochain-bootstrap.service"
                  ))


              def report(label, cpu0, t0):
                  """The server's RSS now, and its CPU since (cpu0, t0), from the unit's accounting."""
                  cpu1, t1 = cpu_ns(), time.monotonic()
                  pid = bootstrap.succeed(
                      "systemctl show -p MainPID --value holochain-bootstrap.service"
                  ).strip()
                  rss_kb = int(bootstrap.succeed(f"ps -o rss= -p {pid}").strip())
                  threads = bootstrap.succeed(f"ps -o nlwp= -p {pid}").strip()
                  peak = bootstrap.succeed(
                      "systemctl show -p MemoryPeak --value holochain-bootstrap.service"
                  ).strip()
                  cpu_pct = (cpu1 - cpu0) / ((t1 - t0) * 1e9) * 100
                  bootstrap.log(
                      f"MEASURE {label}: rss={rss_kb} KiB ({rss_kb / 1024:.1f} MiB)"
                      f" cgroup_memory_peak={peak} B"
                      f" cpu={cpu_pct:.3f}% of one core over {t1 - t0:.0f}s"
                      f" cpu_time={(cpu1 - cpu0) / 1e6:.0f} ms threads={threads}"
                  )


              def window(label, seconds):
                  cpu0, t0 = cpu_ns(), time.monotonic()
                  time.sleep(seconds)
                  report(label, cpu0, t0)


              def app_facts(node):
                  apps = json.loads(node.succeed(f"{CALL} list-apps"))
                  app = next(a for a in apps if a["installed_app_id"] == "kando")
                  dna = sorted(set(re.findall(r"uhC0k[A-Za-z0-9_-]+", json.dumps(app))))
                  assert len(dna) == 1, f"expected one DNA hash, got {dna}"
                  return app["agent_pub_key"], dna[0]


              def agent_infos(node, dna):
                  """Every agent info the conductor holds for the DNA.

                  hc 0.6.3 answers with one object per agent, carrying the
                  peer `url`, which for an iroh peer is
                  `<relay>/<endpoint id>` and so unique to one conductor. It
                  fills `agent_pub_key` only for the conductor's own cells and
                  leaves it null for a remote agent, so a remote agent is
                  recognised by its URL, not its key.
                  """
                  out = node.succeed(f"{CALL} list-agents --dna {dna}")
                  node.log(f"list-agents on {node.name}: {out}")
                  return json.loads(out)


              # ---- the server, alone ----
              bootstrap.start()
              bootstrap.wait_for_unit("holochain-bootstrap.service")
              bootstrap.wait_for_open_port(443)
              bootstrap.succeed("curl -sf http://127.0.0.1:443/health")
              user = bootstrap.succeed(
                  "ps -o user= -p $(systemctl show -p MainPID --value holochain-bootstrap.service)"
              ).strip()
              assert user != "root", "the server runs as root"
              bootstrap.log(f"server runs as dynamic user {user}")
              window("idle, no conductors", 30)

              # ---- two edgenodes on the same seed ----
              exchange_cpu, exchange_t = cpu_ns(), time.monotonic()
              alice.start()
              bob.start()
              for node in [alice, bob]:
                  node.wait_for_unit("holochain-conductor.service")
                  node.wait_for_unit("holochain-happ-installer.service")
                  # The server answers over the vlan, not only on loopback.
                  node.succeed("curl -sf http://bootstrap:443/health")
                  # The config path is on the running conductor's command line.
                  path = node.succeed(
                      "tr '\\0' ' ' < /proc/$(systemctl show -p MainPID --value"
                      " holochain-conductor.service)/cmdline"
                      " | grep -o '/nix/store/[^ ]*conductor-config.yaml'"
                  ).strip()
                  config = node.succeed(f"cat {path}")
                  assert '"relayAllowPlainText":true' in config, config
                  assert "request_timeout_s: 60" in config, config

              alice_id, dna = app_facts(alice)
              bob_id, bob_dna = app_facts(bob)
              assert dna == bob_dna, f"different DNAs: {dna} vs {bob_dna}"
              assert alice_id != bob_id
              alice.log(f"dna={dna} alice={alice_id} bob={bob_id}")


              # iroh writes the relay host as a fully qualified name, with a
              # trailing dot: http://bootstrap.:443/relay/<endpoint id>.
              ON_OUR_RELAY = re.compile(r"^http://bootstrap\.?:443/relay/")


              def own_url(node, key):
                  """The peer URL a conductor published for its own agent, if any yet."""
                  for info in agent_infos(node, dna):
                      if info["agent_pub_key"] == key:
                          return info.get("url")
                  return None


              def sees(node, other, other_key):
                  url = own_url(other, other_key)
                  if url is None or ON_OUR_RELAY.match(url) is None:
                      return False
                  holds_info = any(
                      info.get("url") == url and info["agent_pub_key"] is None
                      for info in agent_infos(node, dna)
                  )
                  # And a live connection to that conductor's endpoint, the
                  # last path segment of its URL.
                  stats = json.loads(node.succeed(f"{CALL} dump-network-stats"))
                  endpoint = url.rstrip("/").rsplit("/", 1)[-1]
                  connected = any(
                      c.get("pub_key") == endpoint
                      for c in stats["transport_stats"]["connections"]
                  )
                  return holds_info and connected


              start = time.monotonic()
              try:
                  with alice.nested("each conductor holds the other's agent info"):
                      retry(lambda _: sees(alice, bob, bob_id) and sees(bob, alice, alice_id), timeout_seconds=300)
              finally:
                  alice.succeed(f"{CALL} dump-network-stats >&2")
                  bob.succeed(f"{CALL} dump-network-stats >&2")
              alice.log(f"MEASURE discovery: both sides saw each other after {time.monotonic() - start:.0f}s")
              report("boot to mutual discovery of two conductors", exchange_cpu, exchange_t)
              window("two conductors connected, steady state", 60)
            '';
          };

        # One machine running an edgenode, the HTTP gateway, Grafana and, when
        # `bootstrap` is true, the local bootstrap and relay. The pass
        # condition is what a person reads through Grafana's own query API:
        # the node page's "Is each service on this machine running?" names
        # every service the enabled modules installed, and nothing else, each
        # Running; with
        # bootstrap, the server frozen reads Not answering while systemd still
        # says active, and stopped reads Stopped, the room screen's tile for
        # the machine turning to A service is down both times.
        #
        # `expectBootstrap` exists for the falsifiers: a test that expects
        # the bootstrap server on a machine without it, or not on one with it,
        # has to fail (legacyPackages.falsifiers).
        servicesTest = {
          name,
          bootstrap ? true,
          expectBootstrap ? bootstrap,
        }:
          pkgs.testers.nixosTest {
            inherit name;
            nodes.machine = {
              imports = [
                edgenodeNode
                roomToWork
                self.nixosModules.holochain-grafana
                self.nixosModules.holochain-http-gateway
                self.nixosModules.holochain-bootstrap
              ];
              environment.systemPackages = [pkgs.jq];
              services.holochain-edgenode = {
                enable = true;
                metricsExporter.enable = true;
                conductorMetrics.enable = true;
              };
              services.holochain-http-gateway.enable = true;
              services.holochain-bootstrap.enable = bootstrap;
              systemd.tmpfiles.rules = [
                "d /var/lib/secrets 0700 root root - -"
                "f /var/lib/secrets/grafana-admin-password 0400 root root - ${grafanaTestPassword}"
              ];
              services.holochain-grafana = {
                enable = true;
                adminPasswordFile = "/var/lib/secrets/grafana-admin-password";
                scrapeTargets.machine.address = "127.0.0.1:9100";
              };
            };
            testScript = ''
              import base64
              import json

              EXPECT_BOOTSTRAP = ${
                if expectBootstrap
                then "True"
                else "False"
              }
              BOOTSTRAP = "Local bootstrap and relay"
              RUNNING, NOT_ANSWERING, STOPPED, FAILED = 6, 2, 1, 0
              TILE_RUNNING, TILE_SERVICE_DOWN = 4, 2

              machine.wait_for_unit("grafana.service")
              machine.wait_for_unit("prometheus.service")
              machine.wait_for_unit("holochain-conductor.service")
              machine.wait_for_open_port(3000)


              def grafana(path):
                  return json.loads(machine.succeed(
                      "curl -sf -u admin:${grafanaTestPassword}"
                      f" 'http://localhost:3000{path}'"
                  ))


              def target(uid, title):
                  panels = grafana(f"/api/dashboards/uid/{uid}")["dashboard"]["panels"]
                  panels = panels + [p for row in panels for p in row.get("panels", [])]
                  expr = next(p for p in panels if p["title"] == title and p["type"] != "row")["targets"][0]["expr"]
                  expr = expr.replace("$node", "machine").replace("$site", ".*")
                  assert "$" not in expr, expr
                  return expr


              # The queries the pages run, as Grafana serves them.
              services_expr = target("holochain-node", "Is each service on this machine running?")
              tile_expr = target("holochain-now", "Which machines are on?")
              down_expr = target("holochain-fleet", "Which services are not running?")
              problems_expr = target("holochain-fleet", "What needs a human?")
              machine.log(f"services query: {services_expr}")


              def ds(expr, name):
                  """One instant query through Grafana's /api/ds/query, as {labels: value}."""
                  body = {
                      "from": "now-5m",
                      "to": "now",
                      "queries": [{
                          "refId": "A",
                          "datasource": {"type": "prometheus", "uid": "holochain-prometheus"},
                          "expr": expr,
                          "instant": True,
                          "range": False,
                          "intervalMs": 15000,
                          "maxDataPoints": 100,
                      }],
                  }
                  encoded = base64.b64encode(json.dumps(body).encode()).decode()
                  machine.succeed(f"echo {encoded} | base64 -d > /tmp/{name}.json")
                  reply = json.loads(machine.succeed(
                      "curl -s -u admin:${grafanaTestPassword} -H 'Content-Type: application/json'"
                      f" -X POST --data @/tmp/{name}.json http://localhost:3000/api/ds/query"
                  ))
                  result = reply["results"]["A"]
                  assert result.get("error") is None, result
                  return [
                      (frame["schema"]["fields"][1].get("labels", {}), frame["data"]["values"][1][-1])
                      for frame in result.get("frames", [])
                      if frame["data"]["values"] and frame["data"]["values"][1]
                  ]


              def services():
                  """The node page's services table: {service name: state code}."""
                  return {labels["service"]: value for labels, value in ds(services_expr, "services")}


              def tile():
                  return {labels["node"]: value for labels, value in ds(tile_expr, "tile")}.get("machine")


              expected = {
                  "Holochain conductor", "Holochain readings (timer)", "HTTP gateway",
                  "Metrics database", "Dashboards", "Machine readings", "Nix",
              } | ({BOOTSTRAP} if EXPECT_BOOTSTRAP else set())


              def all_running(rows, want):
                  return set(rows) == want and all(v == RUNNING for v in rows.values())


              # The check must fail on an answer that is not the one wanted:
              # one service short, one in another state, one too many.
              sample = {n: RUNNING for n in expected}
              assert all_running(sample, expected)
              assert not all_running({n: v for n, v in sample.items() if n != "HTTP gateway"}, expected)
              assert not all_running({**sample, "HTTP gateway": STOPPED}, expected)
              assert not all_running({**sample, "Remote login": RUNNING}, expected)

              last = {}


              def settled(_):
                  global last
                  last = services()
                  return all_running(last, expected)


              try:
                  retry(settled, timeout_seconds=300)
              finally:
                  machine.log("services on the node page: " + json.dumps(last, sort_keys=True))
              # The services can settle before the conductor's first readings
              # reach Prometheus, and until then the machine has no Holochain
              # to show.
              retry(lambda _: tile() == TILE_RUNNING, timeout_seconds=180)

              if not EXPECT_BOOTSTRAP:
                  # Nothing of the server anywhere: no unit, no health reading.
                  assert BOOTSTRAP not in services()
                  machine.fail("systemctl cat holochain-bootstrap.service")
                  machine.fail("curl -s localhost:9100/metrics | grep -q '^holochain_service_healthy'")
              else:
                  health = machine.succeed("curl -s localhost:9100/metrics | grep '^holochain_service_healthy'")
                  machine.log("health reading: " + health)
                  assert 'holochain_service_healthy{name="holochain-bootstrap.service"} 1' in health, health


                  def reads(state):
                      return lambda _: services().get(BOOTSTRAP) == state


                  def listed_down(state):
                      return any(
                          labels.get("service") == BOOTSTRAP and value == state
                          for labels, value in ds(down_expr, "down")
                      )


                  def problem(sentence):
                      return any(labels.get("problem") == sentence for labels, _ in ds(problems_expr, "problems"))


                  # Running but not answering: the server frozen, its unit
                  # still active. The same checks fail while it answers.
                  assert not reads(NOT_ANSWERING)(None)
                  assert not listed_down(NOT_ANSWERING)
                  pid = machine.succeed("systemctl show -p MainPID --value holochain-bootstrap.service").strip()
                  machine.succeed(f"kill -STOP {pid}")
                  retry(reads(NOT_ANSWERING), timeout_seconds=180)
                  assert machine.succeed("systemctl is-active holochain-bootstrap.service").strip() == "active"
                  assert listed_down(NOT_ANSWERING)
                  assert problem(f"{BOOTSTRAP} is not answering")
                  assert tile() == TILE_SERVICE_DOWN, tile()
                  machine.log("frozen: Not answering, while systemd says active")

                  machine.succeed(f"kill -CONT {pid}")
                  retry(reads(RUNNING), timeout_seconds=180)
                  retry(lambda _: tile() == TILE_RUNNING, timeout_seconds=60)

                  # Stopped.
                  assert not reads(STOPPED)(None)
                  machine.succeed("systemctl stop holochain-bootstrap.service")
                  retry(reads(STOPPED), timeout_seconds=120)
                  assert listed_down(STOPPED)
                  assert problem(f"{BOOTSTRAP} is stopped")
                  assert tile() == TILE_SERVICE_DOWN, tile()
                  machine.log("stopped: Stopped")

                  # Failing at every start: systemd restarts it every
                  # RestartSec and calls it activating in between, so only the
                  # restart count tells the loop from a slow start.
                  loop = "failed and systemd is restarting it"
                  assert not reads(FAILED)(None)
                  assert not problem(f"{BOOTSTRAP} {loop}")
                  machine.succeed(
                      "mkdir -p /run/systemd/system/holochain-bootstrap.service.d"
                      " && printf '[Service]\\nExecStart=\\nExecStart=/bin/sh -c \"exit 1\"\\n'"
                      " > /run/systemd/system/holochain-bootstrap.service.d/fail.conf"
                      " && systemctl daemon-reload"
                      " && systemctl start --no-block holochain-bootstrap.service"
                  )
                  retry(lambda _: problem(f"{BOOTSTRAP} {loop}"), timeout_seconds=180)
                  retry(reads(FAILED), timeout_seconds=60)
                  machine.log("systemd: " + machine.succeed(
                      "systemctl show -p ActiveState -p SubState -p NRestarts holochain-bootstrap.service"
                  ).replace("\n", " "))
                  assert int(machine.succeed(
                      "systemctl show -p NRestarts --value holochain-bootstrap.service"
                  )) > 1
                  assert listed_down(FAILED)
                  assert tile() == TILE_SERVICE_DOWN, tile()
                  machine.log("restarting at every failure: Failed")
            '';
          };
      in {
        packages = {
          holochain-0_6 = holonix06.holochain;
          hc-0_6 = holonix06.hc;

          # kitsune2-bootstrap-srv, bootstrap and iroh relay in one binary:
          # 0.4.1 from holonix main-0.6, 0.5.0 from main-0.7. The
          # holochain-bootstrap module defaults to the 0.6 one.
          bootstrap-srv-0_6 = holonix06.bootstrap-srv;
          bootstrap-srv = inputs.holonix.packages.${system}.bootstrap-srv;

          # One gateway build per Holochain line, so an operator can check
          # which binary a node would run without evaluating a whole system.
          # The module picks between them from the conductor's version.
          holochain-http-gateway = gatewayPkgs.callPackage ./packages/holochain-http-gateway.nix {line = "0.7";};
          holochain-http-gateway-0_6 = gatewayPkgs06.callPackage ./packages/holochain-http-gateway.nix {line = "0.6";};

          # The textfile exporter, one per Holochain line because the admin
          # call differs. A conductor that is not an edgenode's own (a Moss
          # node, say) runs the one of its line under its own name.
          holochain-conductor-exporter = conductorExporter;
          holochain-conductor-exporter-0_6 = conductorExporter.override {hc = holonix06.hc;};

          # The committed docs/module-options.md is a copy of this build.
          options-doc = pkgs.runCommand "module-options.md" {} ''
            cat ${optionsDocHeader} ${optionsDoc.optionsCommonMark} > $out
          '';
        };

        # Tests that must FAIL, kept next to the check they falsify so anyone
        # can re-run them. Never in `checks`. Build the driver, run it, and
        # read a non-zero exit as the falsifier holding:
        #   nix build .#legacyPackages.x86_64-linux.falsifiers.vmTestBootstrap-wrongPort.driver
        #   ./result/bin/nixos-test-driver
        legacyPackages.falsifiers = {
          # bob's bootstrap URL points at 444, where nothing listens.
          vmTestBootstrap-wrongPort = bootstrapTest {
            name = "holochain-bootstrap-wrong-port";
            bobBootstrapPort = 444;
          };
          # The services test, expecting the bootstrap server where it does
          # not run, and not expecting it where it does.
          vmTestServices-bootstrapMissing = servicesTest {
            name = "holochain-services-bootstrap-missing";
            bootstrap = false;
            expectBootstrap = true;
          };
          vmTestServices-bootstrapUnexpected = servicesTest {
            name = "holochain-services-bootstrap-unexpected";
            expectBootstrap = false;
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [nixos-rebuild colmena nil nixd alejandra];
        };

        checks = {
          # The #54 passthroughs, rendered on both lines and then handed to
          # that line's real conductor, which rejects unknown keys and bad
          # values: "Conductor ready." is the proof each rendered key is one
          # the conductor accepts, not merely one the module writes. No VM
          # and no network needed; the bootstrap and relay URLs are never
          # reached before readiness.
          edgenodeConfigRender = let
            render = extra:
              (inputs.nixpkgs.lib.nixosSystem {
                inherit system;
                modules = [
                  edgenodeNode
                  extra
                  {
                    services.holochain-edgenode = {
                      enable = true;
                      bootstrapUrl = "http://bootstrap.invalid";
                      relayUrl = "http://bootstrap.invalid/relay";
                      relayAllowPlainText = true;
                      requestTimeoutS = 90;
                      dbSyncLevel = "Off";
                      wasmBackend = "cranelift";
                    };
                  }
                ];
              })
              .config
              .services
              .holochain-edgenode;
            e07 = render {};
            e06 = render on06;
          in
            pkgs.runCommand "edgenode-config-render" {} ''
              has() {
                grep -qxF -- "$2" "$1" || { echo "missing from $1: $2"; cat "$1"; exit 1; }
              }
              lacks() {
                if grep -q -- "$2" "$1"; then echo "unexpected in $1: $2"; cat "$1"; exit 1; fi
              }

              for cfg in ${e07.conductorConfigFile} ${e06.conductorConfigFile}; do
                has "$cfg" '  relay_url: http://bootstrap.invalid/relay'
                has "$cfg" '  request_timeout_s: 90'
                has "$cfg" '  advanced: {"irohTransport":{"relayAllowPlainText":true}}'
              done
              has ${e07.conductorConfigFile} 'db_sync_level: Off'
              has ${e07.conductorConfigFile} 'wasm_backend: cranelift'
              # Below 0.7 both keys are unknown to the conductor.
              lacks ${e06.conductorConfigFile} 'db_sync_level'
              lacks ${e06.conductorConfigFile} 'wasm_backend'

              # Each line's conductor on its own rendered config. The data root
              # moves under the build directory, whose path is short enough
              # for lair's unix socket.
              ready() {
                name=$1 conductor=$2 cfg=$3
                mkdir -p "$TMPDIR/$name"
                sed "s|/var/lib/holochain|$TMPDIR/$name|g" "$cfg" > "$name.yaml"
                echo pass | "$conductor" --piped -c "$name.yaml" > "$name.log" 2>&1 &
                pid=$!
                for _ in $(seq 1 120); do
                  if grep -q "Conductor ready" "$name.log"; then
                    echo "$name: Conductor ready"
                    kill "$pid"
                    wait "$pid" || true
                    return 0
                  fi
                  sleep 1
                done
                echo "$name: the conductor never became ready on its rendered config"
                cat "$name.yaml" "$name.log"
                exit 1
              }
              ready h07 ${pkgs.lib.getExe' e07.package "holochain"} ${e07.conductorConfigFile}
              ready h06 ${pkgs.lib.getExe' e06.package "holochain"} ${e06.conductorConfigFile}
              touch $out
            '';

          # The metrics jq against replies a bare conductor in a VM never
          # produces: live connections, nested blocked_message_counts, installed
          # apps, and a peer disconnecting between two runs. One malformed line
          # makes node_exporter drop the whole textfile, so the output must pass
          # promtool as well as carry the right sums.
          conductorMetricsJq =
            pkgs.runCommand "conductor-metrics-jq" {
              nativeBuildInputs = [pkgs.jq pkgs.prometheus.cli];
            } ''
              cat > busy.json <<'EOF'
              {"transport_stats":{"backend":"iroh","peer_urls":["u1","u2"],
                "connections":[
                  {"pub_key":"a","send_message_count":3,"send_bytes":100,"recv_message_count":4,"recv_bytes":200,"opened_at_s":1,"is_direct":true},
                  {"pub_key":"b","send_message_count":5,"send_bytes":50,"recv_message_count":1,"recv_bytes":10,"opened_at_s":2,"is_direct":false}]},
               "blocked_message_counts":{"space1":{"reasonA":{"incoming":2,"outgoing":3}},"space2":{"reasonB":{"incoming":1,"outgoing":0}}}}
              EOF
              # b has disconnected and a has moved 20 more bytes; c is new, and
              # a reconnected under a new opened_at_s is a new connection too.
              cat > later.json <<'EOF'
              {"transport_stats":{"backend":"iroh","peer_urls":["u1"],
                "connections":[
                  {"pub_key":"a","send_message_count":4,"send_bytes":120,"recv_message_count":4,"recv_bytes":200,"opened_at_s":1,"is_direct":true},
                  {"pub_key":"c","send_message_count":1,"send_bytes":7,"recv_message_count":0,"recv_bytes":0,"opened_at_s":9,"is_direct":false}]},
               "blocked_message_counts":{}}
              EOF
              cat > apps.json <<'EOF'
              [{"installed_app_id":"x","status":{"type":"enabled"}},
               {"installed_app_id":"y","status":{"type":"disabled","value":{"reason":"user"}}},
               {"installed_app_id":"z","status":{"type":"awaiting_memproofs"}}]
              EOF

              # prev is a state file's contents; prints the textfile and leaves
              # the new state in state.json, as the timer's script does.
              run() {
                jq -c --argjson prev "$2" -f ${jqLib}/conductor-counters.jq < "$1" > state.json
                jq -r -L ${jqLib} --arg conductor "''${4:-Workshop}" --argjson up 1 --argjson now 1700000000 \
                  --argjson totals "$(jq -c .totals state.json)" --argjson apps "$3" \
                  -f ${jqLib}/conductor-metrics.jq < "$1"
              }

              echo '{}' > empty.json
              for input in busy.json empty.json; do
                for apps in null '[]' "$(cat apps.json)"; do
                  run "$input" '{}' "$apps" > out.prom
                  cat out.prom
                  promtool check metrics < out.prom
                done
              done

              run busy.json '{}' "$(cat apps.json)" > out.prom
              grep -qx 'holochain_conductor_blocked_messages_total{conductor="Workshop"} 6' out.prom
              grep -qx 'holochain_conductor_peer_connections{conductor="Workshop"} 2' out.prom
              grep -qx 'holochain_conductor_direct_peer_connections{conductor="Workshop"} 1' out.prom
              grep -qx 'holochain_conductor_network_sent_bytes_total{conductor="Workshop"} 150' out.prom
              grep -qx 'holochain_conductor_apps{conductor="Workshop",status="enabled"} 1' out.prom
              grep -qx 'holochain_conductor_apps{conductor="Workshop",status="disabled"} 1' out.prom
              grep -qx 'holochain_conductor_apps{conductor="Workshop",status="awaiting_memproofs"} 1' out.prom

              # The totals only go up: 150 + a's 20 more + c's 7, although b and
              # its 50 bytes are gone from the reply.
              run later.json "$(cat state.json)" null > out.prom
              cat out.prom
              grep -qx 'holochain_conductor_network_sent_bytes_total{conductor="Workshop"} 177' out.prom
              grep -qx 'holochain_conductor_network_sent_messages_total{conductor="Workshop"} 10' out.prom
              grep -qx 'holochain_conductor_network_received_bytes_total{conductor="Workshop"} 210' out.prom
              if grep -q '^holochain_conductor_apps' out.prom; then
                echo "an unanswered list-apps must not read as zero apps" >&2
                exit 1
              fi

              # A down conductor answers nothing: the totals hold.
              run empty.json "$(cat state.json)" '[]' > out.prom
              grep -qx 'holochain_conductor_network_sent_bytes_total{conductor="Workshop"} 177' out.prom
              grep -qx 'holochain_conductor_apps{conductor="Workshop",status="enabled"} 0' out.prom
              grep -qx 'holochain_conductor_apps{conductor="Workshop",status="disabled"} 0' out.prom

              # Every line names its conductor, and a name is free text: a
              # quote, a backslash and a newline in it are escaped, and no line
              # of the file is left without the label.
              run busy.json '{}' "$(cat apps.json)" "$(printf 'Mo"ss\\\nx')" > odd.prom
              cat odd.prom
              promtool check metrics < odd.prom
              grep -qxF 'holochain_conductor_up{conductor="Mo\"ss\\\nx"} 1' odd.prom
              grep -qxF 'holochain_conductor_apps{conductor="Mo\"ss\\\nx",status="enabled"} 1' odd.prom
              if grep -v '^#' odd.prom | grep -vF '{conductor="Mo\"ss\\\nx"'; then
                echo "a sample line without the conductor label" >&2
                exit 1
              fi
              touch $out
            '';

          # The per-DHT jq against replies captured from two real conductors:
          # a Holochain 0.6.1 Moss group node in seven DHTs and the homelab's
          # 0.6.3 edgenode conductor with three apps in four (both 2026-09-27;
          # network seeds redacted, nothing the jq reads changed), against the
          # ways the calls fail, against names files good and bad, and against
          # label values that would break the textfile if they reached it
          # unescaped. Every output goes through promtool, alone and appended
          # to the conductor series as the exporter writes it.
          dhtMetricsJq =
            pkgs.runCommand "dht-metrics-jq" {
              nativeBuildInputs = [pkgs.jq pkgs.prometheus.cli];
            } ''
              apps=${./tests/fixtures/dht-0_6_1/list-apps.json}
              metrics=${./tests/fixtures/dht-0_6_1/dump-network-metrics.json}
              ws_apps=${./tests/fixtures/edgenode-0_6_3/list-apps.json}
              ws_metrics=${./tests/fixtures/edgenode-0_6_3/dump-network-metrics.json}

              # The three documents on stdin, list-apps first and the names
              # file last, as the exporter passes them; the conductor is Moss
              # unless a fourth argument names another.
              dht() {
                printf '%s\n%s\n%s\n' "$1" "$2" "''${3:-null}" \
                  | jq -n -r -L ${jqLib} --arg conductor "''${4:-Moss}" --argjson now 1790484800 \
                      -f ${jqLib}/dht-metrics.jq
              }

              # No two apps of one conductor share an app_name, and no two of
              # its DHTs share a network_label, or a dashboard would draw two
              # things under one name.
              names_unique() {
                { grep '^holochain_app_info{' "$1" || true; } \
                  | sed -E 's/^holochain_app_info\{conductor="((\\.|[^"\\])*)",app_id="((\\.|[^"\\])*)",app_name="((\\.|[^"\\])*)",.*/\1 \5/' \
                  | sort > app.names
                { grep '^holochain_dht_info{' "$1" || true; } \
                  | sed -E 's/^holochain_dht_info\{conductor="((\\.|[^"\\])*)",.*,network_label="((\\.|[^"\\])*)"\} 1$/\1 \3/' \
                  | sort > network.names
                for f in app.names network.names; do
                  if [ -n "$(uniq -d $f)" ]; then
                    echo "$1: names shared by two of one conductor's items in $f:" >&2
                    uniq -d $f >&2
                    exit 1
                  fi
                done
              }

              # Every data series has exactly one info row with the same key,
              # and the other way round; then the names are distinct.
              keys_match() {
                grep '^holochain_dht_peers{' "$1" | sed -E 's/^holochain_dht_peers\{(.*)\} [-0-9]+$/\1/' | sort > data.keys
                grep '^holochain_dht_info{' "$1" \
                  | sed -E 's/^holochain_dht_info\{(conductor="[^"]*",app_id="[^"]*",role="[^"]*",dna="[^"]*"),.*/\1/' | sort > info.keys
                diff data.keys info.keys
                test "$(sort -u info.keys | wc -l)" = "$(wc -l < info.keys)"
                names_unique "$1"
              }

              dht "$(cat $apps)" "$(cat $metrics)" > out.prom
              cat out.prom
              promtool check metrics < out.prom

              # Seven DHTs, seven series of each metric, one name row each.
              for name in peers local_ops peer_ops pending_fetches seconds_since_gossip \
                completed_rounds_total peer_timeouts_total info; do
                n=$(grep -c "^holochain_dht_$name{" out.prom)
                test "$n" = 7 || { echo "holochain_dht_$name: $n series, expected 7" >&2; exit 1; }
              done
              keys_match out.prom
              # Data series carry machine keys only; `app` became app_id.
              if grep -E '^holochain_dht_[a-z_]+\{' out.prom | grep -v '^holochain_dht_info' \
                | grep -E '[{,](app|app_name|app_kind|part_name|network_label)="'; then
                echo "a data series carries a name label" >&2
                exit 1
              fi

              # The group DHT, read by hand from the fixture: one peer holding
              # 975 ops against 948 here, 61 rounds, last gossip at
              # 1790484723.53 s, so 76.47 s before the fixed now, floored.
              group='conductor="Moss",app_id="group#4zHNh4L9G9Lr7b6l/lmOORVbiNB2CaUzjKoqLgUR7UE=#null",role="group",dna="uhC0kDTZE5JwUHP9yIz2Bhjq2TPdkLSNhJtqTdq5RzS7vFPfrIvJY"'
              grep -qxF "holochain_dht_peers{$group} 1" out.prom
              grep -qxF "holochain_dht_local_ops{$group} 948" out.prom
              grep -qxF "holochain_dht_peer_ops{$group} 975" out.prom
              grep -qxF "holochain_dht_pending_fetches{$group} 0" out.prom
              grep -qxF "holochain_dht_completed_rounds_total{$group} 61" out.prom
              grep -qxF "holochain_dht_peer_timeouts_total{$group} 0" out.prom
              grep -qxF "holochain_dht_seconds_since_gossip{$group} 76" out.prom

              # Two applets of one tool share role names; the app_id label keeps
              # them apart. The second has never gossiped: -1, not a huge age.
              grep -c '^holochain_dht_peers{.*role="rVines"' out.prom | grep -qx 2
              grep '^holochain_dht_seconds_since_gossip{' out.prom | grep -F k1h2cpht | grep -F 'role="rVines"' | grep -q ' -1$'

              # With no names file, Moss names come from the bundles: the two
              # chats of one tool are numbered in installed_app_id order, the
              # group is Group, and a role reads as its id without its prefix,
              # or as Main where that would only repeat the app's kind.
              grep -qxF 'holochain_dht_info{conductor="Moss",app_id="applet#uhc$e$k1h2cpht$kfgs$v$l$t$3zhz-b$d_b$t$5kq$lyybe$vs$6lb$xzzsgd$hu$5ry$",role="rFiles",dna="uhC0kujTsC4x0m_WoAtP-Ct0WJtsAK8cK-UAOsIgvY0q30XjbFbRj",app_name="Vines 1",app_kind="Vines",part_name="Files",network_label="Vines 1: Files"} 1' out.prom
              grep -qF 'app_name="Vines 1",app_kind="Vines",part_name="Main",network_label="Vines 1: Main"} 1' out.prom
              grep -qxF 'holochain_app_info{conductor="Moss",app_id="applet#uhc$e$krun4ink$1nl$paibamp$j$j3r$t$egt$57b$rc$ue$c$2j$bd$1a$k$hbh$g$p$zu$l$",app_name="Vines 2",app_kind="Vines",status="enabled"} 1' out.prom
              grep -qxF "holochain_dht_info{$group,app_name=\"Group\",app_kind=\"Group\",part_name=\"Main\",network_label=\"Group: Main\"} 1" out.prom
              test "$(grep -c '^holochain_app_info{' out.prom)" = 3

              # A Moss names file: the group's name, one chat's name, a part
              # table per kind. The unnamed chat keeps its number.
              cat > moss-names.json <<'EOF'
              {"apps":{"group#4zHNh4L9G9Lr7b6l/lmOORVbiNB2CaUzjKoqLgUR7UE=#null":{"name":"Sensorica"},
                       "applet#uhc$e$krun4ink$1nl$paibamp$j$j3r$t$egt$57b$rc$ue$c$2j$bd$1a$k$hbh$g$p$zu$l$":{"name":"General chat"}},
               "kinds":{"Vines":{"rVines":"Messages","rFiles":"Files"},
                        "Group":{"group":"Members and tools","foyer":"Foyer","assets":"Shared assets"}}}
              EOF
              dht "$(cat $apps)" "$(cat $metrics)" "$(cat moss-names.json)" > named.prom
              cat named.prom
              promtool check metrics < named.prom
              keys_match named.prom
              grep -qxF "holochain_dht_info{$group,app_name=\"Sensorica\",app_kind=\"Group\",part_name=\"Members and tools\",network_label=\"Sensorica: Members and tools\"} 1" named.prom
              grep -qxF 'holochain_dht_info{conductor="Moss",app_id="applet#uhc$e$krun4ink$1nl$paibamp$j$j3r$t$egt$57b$rc$ue$c$2j$bd$1a$k$hbh$g$p$zu$l$",role="rVines",dna="uhC0kjGGg7aTaaHUDdSQgoqNAGekaa9rYCe0DjK6RwDr5KaaRaZeD",app_name="General chat",app_kind="Vines",part_name="Messages",network_label="General chat: Messages"} 1' named.prom
              grep -qF 'app_name="Vines 1",app_kind="Vines",part_name="Messages",network_label="Vines 1: Messages"} 1' named.prom
              # Names never touch the data series.
              grep -v '_info' out.prom > out.data
              grep -v '_info' named.prom > named.data
              diff out.data named.data

              # The Moss conductor stopped: the wrapper's names file still
              # lists every app it has seen as expected, one of them with its
              # kind. Nothing is named after its id, a group is still a Group,
              # and a tool is its given kind, else Tool, numbered like the
              # chats above.
              G='group#4zHNh4L9G9Lr7b6l/lmOORVbiNB2CaUzjKoqLgUR7UE=#null'
              A1='applet#uhc$e$krun4ink$1nl$paibamp$j$j3r$t$egt$57b$rc$ue$c$2j$bd$1a$k$hbh$g$p$zu$l$'
              A2='applet#uhc$e$k1h2cpht$kfgs$v$l$t$3zhz-b$d_b$t$5kq$lyybe$vs$6lb$xzzsgd$hu$5ry$'
              jq --arg g "$G" --arg a1 "$A1" --arg a2 "$A2" \
                '.expected = [$g, $a1, $a2] | .apps[$a1].kind = "Vines"' moss-names.json > moss-seen.json
              dht null null "$(cat moss-seen.json)" > moss-down.prom
              cat moss-down.prom
              promtool check metrics < moss-down.prom
              names_unique moss-down.prom
              grep -qxF "holochain_app_info{conductor=\"Moss\",app_id=\"$G\",app_name=\"Sensorica\",app_kind=\"Group\",status=\"expected\"} 1" moss-down.prom
              grep -qxF "holochain_app_info{conductor=\"Moss\",app_id=\"$A1\",app_name=\"General chat\",app_kind=\"Vines\",status=\"expected\"} 1" moss-down.prom
              grep -qxF "holochain_app_info{conductor=\"Moss\",app_id=\"$A2\",app_name=\"Tool\",app_kind=\"Tool\",status=\"expected\"} 1" moss-down.prom
              jq '.expected = [.apps | keys[]] + ["applet#uhc$x", "applet#uhc$y"] | del(.apps[].name)' moss-seen.json > moss-bare-seen.json
              dht null null "$(cat moss-bare-seen.json)" > moss-bare-down.prom
              cat moss-bare-down.prom
              names_unique moss-bare-down.prom
              grep -qF 'app_id="group#4zHNh4L9G9Lr7b6l/lmOORVbiNB2CaUzjKoqLgUR7UE=#null",app_name="Group",app_kind="Group",status="expected"' moss-bare-down.prom
              grep -qF 'app_id="applet#uhc$x",app_name="Tool 1",app_kind="Tool",status="expected"' moss-bare-down.prom
              grep -qF 'app_id="applet#uhc$y",app_name="Tool 2",app_kind="Tool",status="expected"' moss-bare-down.prom
              if grep -F 'app_name="' moss-down.prom moss-bare-down.prom | grep -E 'app_(name|kind)="[^"]*[$#]'; then
                echo "an expected Moss app is named after its id" >&2
                exit 1
              fi

              # A given name can match another app's fallback, or another given
              # name. Each app still gets a name of its own, the given one kept
              # where it can be.
              cat > clash-apps.json <<'EOF'
              [{"installed_app_id":"x","status":{"type":"enabled"},"manifest":{"name":"kando"},"cell_info":{}},
               {"installed_app_id":"y","status":{"type":"enabled"},"manifest":{"name":"board"},"cell_info":{}},
               {"installed_app_id":"p","status":{"type":"enabled"},"manifest":{"name":"p"},"cell_info":{}},
               {"installed_app_id":"q","status":{"type":"enabled"},"manifest":{"name":"q"},"cell_info":{}}]
              EOF
              dht "$(cat clash-apps.json)" '{}' '{"apps":{"y":{"name":"Kando"},"p":{"name":"Chat"},"q":{"name":"Chat"}}}' W > clash.prom
              cat clash.prom
              names_unique clash.prom
              grep -qxF 'holochain_app_info{conductor="W",app_id="y",app_name="Kando",app_kind="Kando",status="enabled"} 1' clash.prom
              grep -qxF 'holochain_app_info{conductor="W",app_id="x",app_name="Kando 2",app_kind="Kando 2",status="enabled"} 1' clash.prom
              grep -qxF 'holochain_app_info{conductor="W",app_id="p",app_name="Chat",app_kind="Chat",status="enabled"} 1' clash.prom
              grep -qxF 'holochain_app_info{conductor="W",app_id="q",app_name="Chat 2",app_kind="Chat 2",status="enabled"} 1' clash.prom

              # The edgenode shape, with a names file typed in the shape the
              # module writes (checks.edgenodeNamesWiring runs the module's
              # own): a display name and role names for one app, the bundle's
              # name for the others, and a one-role app's network named by the
              # app alone.
              cat > ws-names.json <<'EOF'
              {"apps":{"requests-and-offers":{"name":"Requests & Offers",
                         "roles":{"requests_and_offers":"Listings","hrea":"Accounting"}}},
               "kinds":{},"expected":["hrea","kando","requests-and-offers","not-installed"]}
              EOF
              dht "$(cat $ws_apps)" "$(cat $ws_metrics)" "$(cat ws-names.json)" Workshop > ws.prom
              cat ws.prom
              promtool check metrics < ws.prom
              keys_match ws.prom
              test "$(grep -c '^holochain_dht_info{' ws.prom)" = 4
              grep -qxF 'holochain_dht_info{conductor="Workshop",app_id="requests-and-offers",role="requests_and_offers",dna="uhC0k5Kg49j1kwUFmDlTqLBXoQAZHQdutkEojX0m_OKSqBtERwBOY",app_name="Requests & Offers",app_kind="Requests & Offers",part_name="Listings",network_label="Requests & Offers: Listings"} 1' ws.prom
              grep -qxF 'holochain_dht_info{conductor="Workshop",app_id="kando",role="kando",dna="uhC0kFujhaUaX5mZCE1BbC-ZtzLJMNr3-wyIDKd4N1Tn6Avrfk8cD",app_name="Kando",app_kind="Kando",part_name="",network_label="Kando"} 1' ws.prom
              grep -qxF 'holochain_app_info{conductor="Workshop",app_id="hrea",app_name="Hrea",app_kind="Hrea",status="enabled"} 1' ws.prom
              grep -qxF 'holochain_app_info{conductor="Workshop",app_id="requests-and-offers",app_name="Requests & Offers",app_kind="Requests & Offers",status="enabled"} 1' ws.prom
              # Expected by Nix and not listed: there, and not running.
              grep -qxF 'holochain_app_info{conductor="Workshop",app_id="not-installed",app_name="Not installed",app_kind="Not installed",status="expected"} 1' ws.prom
              test "$(grep -c '^holochain_app_info{' ws.prom)" = 4

              # list-apps did not answer: every app Nix expects is written as
              # expected, and nothing else is.
              dht null "$(cat $ws_metrics)" "$(cat ws-names.json)" Workshop > down.prom
              cat down.prom
              promtool check metrics < down.prom
              grep -qxF 'holochain_app_info{conductor="Workshop",app_id="requests-and-offers",app_name="Requests & Offers",app_kind="Requests & Offers",status="expected"} 1' down.prom
              grep -qxF 'holochain_app_info{conductor="Workshop",app_id="kando",app_name="Kando",app_kind="Kando",status="expected"} 1' down.prom
              test "$(grep -c '^holochain_app_info{' down.prom)" = 4
              test "$(grep -c -v '^#\|^holochain_app_info{' down.prom)" = 0

              # A names file of the wrong shape costs the names, not the series.
              for bad in '[]' '"x"' '{"apps":[],"kinds":"x","expected":"x"}' \
                '{"apps":{"kando":"Kando"}}' '{"apps":{"kando":{"name":7,"roles":["x"]}}}'; do
                dht "$(cat $ws_apps)" "$(cat $ws_metrics)" "$bad" Workshop > bad.prom
                promtool check metrics < bad.prom
                test "$(grep -c '^holochain_dht_peers{' bad.prom)" = 4
                grep -qF 'app_id="kando",role="kando",dna="uhC0kFujhaUaX5mZCE1BbC-ZtzLJMNr3-wyIDKd4N1Tn6Avrfk8cD",app_name="Kando"' bad.prom
              done

              # A failed call writes no DHT series rather than zeros; list-apps
              # alone still names the apps.
              dht null "$(cat $metrics)" > failed.prom
              dht "$(cat $apps)" null >> failed.prom
              dht null null >> failed.prom
              dht "$(cat $apps)" '{}' >> failed.prom
              dht '[]' "$(cat $metrics)" >> failed.prom
              if grep -q '^holochain_dht_' failed.prom; then
                echo "per-DHT series without both replies" >&2
                exit 1
              fi
              test -z "$(dht null null)"
              test -z "$(dht '[]' "$(cat $metrics)")"
              test "$(dht "$(cat $apps)" null | grep -c '^holochain_app_info{')" = 3

              # Hostile and malformed input: a quote, a backslash and a newline
              # in an app id and in the conductor name, a stem cell without a
              # cell_id, two cloned cells (one with a clone_id, one without), a
              # DNA the reply does not mention, and fields of the wrong type.
              cat > odd-apps.json <<'EOF'
              [{"installed_app_id":"we\"ird\\app\nid","status":{"type":"enabled"},
                "cell_info":{"main":[
                  {"type":"provisioned","value":{"cell_id":{"dna_hash":"dnaA","agent_pub_key":"k"}}},
                  {"type":"cloned","value":{"clone_id":"main.2","cell_id":{"dna_hash":"dnaB","agent_pub_key":"k"}}},
                  {"type":"cloned","value":{"cell_id":{"dna_hash":"dnaE","agent_pub_key":"k"}}},
                  {"type":"stem","value":{"original_dna_hash":"dnaC"}}],
                 "gone":[{"type":"provisioned","value":{"cell_id":{"dna_hash":"dnaD","agent_pub_key":"k"}}}]}}]
              EOF
              cat > odd-metrics.json <<'EOF'
              {"dnaA":{"fetch_state_summary":{"pending_requests":{"op1":["u"],"op2":["u"]}},
                       "gossip_state_summary":{"peer_meta":{
                         "u1":{"last_gossip_timestamp":1790484790000000,"completed_rounds":2,"peer_timeouts":1,"dht_op_count":10},
                         "u2":{"last_gossip_timestamp":null,"completed_rounds":"x","peer_timeouts":null,"dht_op_count":12}},
                         "local_op_count":11}},
               "dnaB":{"fetch_state_summary":null,"gossip_state_summary":{"peer_meta":null,"local_op_count":null}},
               "dnaE":{}}
              EOF
              dht "$(cat odd-apps.json)" "$(cat odd-metrics.json)" null "$(printf 'M"o\\\ns')" > odd.prom
              cat odd.prom
              promtool check metrics < odd.prom
              key='conductor="M\"o\\\ns",app_id="we\"ird\\app\nid",role="main"'
              test "$(grep -c '^holochain_dht_peers{' odd.prom)" = 3
              # The clones share conductor, app_id and role with the cell they
              # came from, so each gets a name of its own: the clone index plus
              # one from its clone_id, else its place among the role's clones.
              names_unique odd.prom
              for want in 'dnaA:Main' 'dnaB:Main (clone 3)' 'dnaE:Main (clone 2)'; do
                grep -F "holochain_dht_info{$key,dna=\"''${want%%:*}\"," odd.prom | grep -qF "part_name=\"''${want#*:}\","
              done
              grep -qF "holochain_dht_peers{$key,dna=\"dnaA\"} 2" odd.prom
              grep -qF "holochain_dht_pending_fetches{$key,dna=\"dnaA\"} 2" odd.prom
              grep -qF "holochain_dht_peer_ops{$key,dna=\"dnaA\"} 12" odd.prom
              grep -qF "holochain_dht_seconds_since_gossip{$key,dna=\"dnaA\"} 10" odd.prom
              grep -qF "holochain_dht_completed_rounds_total{$key,dna=\"dnaA\"} 2" odd.prom
              grep -qF "holochain_dht_seconds_since_gossip{$key,dna=\"dnaB\"} -1" odd.prom
              # The escaped app id reaches the names too, prettified.
              grep -qF 'holochain_app_info{conductor="M\"o\\\ns",app_id="we\"ird\\app\nid",app_name="We\"ird\\app\nid"' odd.prom
              if grep -q 'dnaC\|dnaD' odd.prom; then
                echo "a stem cell or a DNA outside the reply got series" >&2
                exit 1
              fi

              # The file as the exporter writes it: conductor series, then the
              # names and the DHT series, for each shape.
              for f in out.prom named.prom ws.prom; do
                echo '{}' | jq -r -L ${jqLib} --arg conductor Moss --argjson up 1 --argjson now 1790484800 --argjson totals '{}' \
                  --argjson apps '[{"status":{"type":"enabled"}}]' -f ${jqLib}/conductor-metrics.jq > whole.prom
                cat $f >> whole.prom
                promtool check metrics < whole.prom
              done
              touch $out
            '';

          # The whole exporter, run for an edgenode-shaped and a Moss-shaped
          # conductor on captured replies (tests/metrics.nix): the two files
          # declare every shared family with the same bytes and a real
          # node_exporter keeps both, and no name a dashboard shows is a hash.
          inherit (metricsChecks) metricsHelpAgreement metricsNameShape;

          # The provisioned dashboards, with no VM (tests/dashboards.nix): no
          # label but a human one reaches a legend, a display name, a table
          # column or a stat's field, no text shows a variable holding a key,
          # every panel is described and every uid is its own; every stand-in
          # value (1e9, an empty cell) reads as its word in its colour; and
          # every Holochain query of every dashboard answers, through the rule
          # file, on the homelab's two conductors plus a clone cell, the node
          # reading its worst conductor, with every series it reads there and
          # every rule it names recorded. Each is also run on broken input and
          # must then fail.
          inherit
            (import ./tests/dashboards.nix {
              inherit pkgs jqLib;
              rules = holochainRulesFile;
              inherit (metricsChecks) runs;
            })
            dashboardLabels
            dashboardWords
            dashboardQueries
            ;

          # The recording rules every dashboard reads, under promtool's rule
          # tests: a node alone, nodes in step and catching up, contact lost
          # three ways, readings that stop, the homelab's two conductors from
          # the exporter's jq on the captured replies, an app expected and not listed, DHTs
          # with no name, node states, conductors under the default name, a
          # machine in trouble and a healthy one. Each
          # expectation is also broken on its own and must then fail.
          holochainRules = import ./tests/rules.nix {
            inherit pkgs;
            rules = holochainRulesFile;
            overviewRulesFor = units: builtins.head (monitor [{services.holochain-grafana.overviewUnits = units;}]).services.prometheus.ruleFiles;
            textfiles = fixtureTextfiles;
          };

          # What the grafana module renders, from evaluated systems: node and
          # site labels per scrape target, the refusal of two targets sharing
          # a node name, the rule file with non-default states, and the
          # dashboard rewrite (units, unit names, room constants).
          grafanaProvisioning = import ./tests/provisioning.nix {
            inherit pkgs monitor;
            modules = {
              edgenode = edgenodeNode;
              inherit (self.nixosModules) holochain-http-gateway holochain-bootstrap holochain-windtunnel;
            };
          };

          # The edgenode module's own names wiring, which the checks above
          # only mimic by hand: an evaluated system's metrics unit, run with
          # the exporter binary swapped for one that prints its arguments, so
          # the shell quoting is the unit's own. Its --conductor must be
          # conductorMetrics.name, and its --names file, fed with the captured
          # edgenode replies through the jq the exporter runs, must name the
          # apps from displayName and roleNames and expect exactly the apps
          # installed = true.
          edgenodeNamesWiring = let
            noHapp = pkgs.writeText "unused.happ" "";
            node = inputs.nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                edgenodeNode
                {
                  services.holochain-edgenode = {
                    enable = true;
                    metricsExporter.enable = true;
                    conductorMetrics = {
                      enable = true;
                      name = "The Workshop";
                    };
                    happs = {
                      requests-and-offers = {
                        src = noHapp;
                        displayName = "Requests & Offers";
                        roleNames = {
                          requests_and_offers = "Listings";
                          hrea = "Accounting";
                        };
                      };
                      kando.src = noHapp;
                      hrea = {
                        src = noHapp;
                        displayName = "Accounting";
                      };
                      retired = {
                        src = noHapp;
                        installed = false;
                      };
                    };
                  };
                }
              ];
            };
            unit = node.config.systemd.services.holochain-conductor-metrics;
          in
            pkgs.runCommand "edgenode-names-wiring" {
              nativeBuildInputs = [pkgs.jq pkgs.prometheus.cli];
            } ''
              script=${unit.serviceConfig.ExecStart}
              cat $script
              sed -E 's|^exec [^ ]*/bin/holochain-conductor-exporter |exec printf "%s\\n" |' $script > args.sh
              grep -q '^exec printf' args.sh
              bash args.sh > args
              cat args
              arg() { sed -n "/^--$1\$/{n;p;q}" args; }
              test "$(arg conductor)" = "The Workshop"
              names=$(arg names)
              jq . "$names"

              jq -e '.expected == ["hrea", "kando", "requests-and-offers"]' "$names"
              printf '%s\n%s\n%s\n' "$(cat ${./tests/fixtures/edgenode-0_6_3/list-apps.json})" \
                "$(cat ${./tests/fixtures/edgenode-0_6_3/dump-network-metrics.json})" "$(cat "$names")" \
                | jq -n -r -L ${jqLib} --arg conductor "$(arg conductor)" --argjson now 1790484800 \
                    -f ${jqLib}/dht-metrics.jq > ws.prom
              cat ws.prom
              promtool check metrics < ws.prom
              grep -qF 'holochain_dht_info{conductor="The Workshop",app_id="requests-and-offers",role="requests_and_offers",dna="uhC0k5Kg49j1kwUFmDlTqLBXoQAZHQdutkEojX0m_OKSqBtERwBOY",app_name="Requests & Offers",app_kind="Requests & Offers",part_name="Listings",network_label="Requests & Offers: Listings"} 1' ws.prom
              grep -qF 'app_id="requests-and-offers",role="hrea",' ws.prom
              grep '^holochain_dht_info{' ws.prom | grep -F 'app_id="requests-and-offers",role="hrea",' | grep -qF 'network_label="Requests & Offers: Accounting"'
              grep -qF 'holochain_app_info{conductor="The Workshop",app_id="hrea",app_name="Accounting",app_kind="Accounting",status="enabled"} 1' ws.prom
              grep -qF 'holochain_app_info{conductor="The Workshop",app_id="kando",app_name="Kando",app_kind="Kando",status="enabled"} 1' ws.prom
              if grep -q 'retired' ws.prom; then
                echo "an app with installed = false is expected" >&2
                exit 1
              fi
              touch $out
            '';

          # One node wearing both roles: an edgenode exporting its conductor's
          # own stats, and the monitor scraping and drawing them. That is the
          # whole observability path in a single VM, so a break anywhere in it
          # fails here rather than at the workshop.
          vmTestGrafana = pkgs.testers.nixosTest {
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
                # An app gives the conductor DHTs, without which the per-DHT
                # panels would have no series to query.
                happs.dino-adventure = {
                  src = dinoAdventureHapp;
                  networkSeed = "ci-test-seed";
                };
              };
              # Root-owned 0400, as the option reference tells operators to
              # create it: systemd reads it, the grafana user never does.
              systemd.tmpfiles.rules = [
                "d /var/lib/secrets 0700 root root - -"
                "f /var/lib/secrets/grafana-admin-password 0400 root root - ${grafanaTestPassword}"
              ];
              services.holochain-grafana = {
                enable = true;
                # The file path, not the plaintext option: this is what the
                # fleet uses, and the credential hand-off is what can break.
                adminPasswordFile = "/var/lib/secrets/grafana-admin-password";
                # The second target has nothing listening, so the dashboard
                # has a node that is down to show, next to one that is up.
                # Named, as a homelab names its nodes: both are on loopback,
                # where a list would name both after this machine.
                scrapeTargets = {
                  machine = {
                    address = "127.0.0.1:9100";
                    site = "CI";
                  };
                  unplugged.address = deadTarget;
                };
                openFirewall = true;
                # Added to the default list rather than replacing it, both at
                # option-default priority, so the test sees the default units
                # and proves the option reaches the provisioned JSON.
                overviewUnits = pkgs.lib.mkOptionDefault ["systemd-journald.service" "always-fails.service"];
                # The Workshop fixture's app, so the room screen's write chart
                # has lines once the fixtures are written.
                room = {
                  app = "requests-and-offers";
                  part = "requests_and_offers";
                  label = "Requests & Offers";
                };
              };
              # A unit in the failed state, for the Overview to show as one.
              systemd.services.always-fails = {
                description = "A unit that always fails, for vmTestGrafana";
                wantedBy = ["multi-user.target"];
                script = "exit 1";
              };
              # One that fails and is not watched: the problem list still
              # names it, since no panel that filters on the watched units
              # would.
              systemd.services.fails-unwatched = {
                description = "A unit that always fails and is not in overviewUnits, for vmTestGrafana";
                wantedBy = ["multi-user.target"];
                script = "exit 1";
              };
            };
            testScript = {nodes, ...}: let
              # Two more conductors on this node, Workshop and Moss, as the
              # exporter writes them, in textfiles of their own beside the
              # live conductor's. Their readings are dated an hour ahead, so
              # they stay fresh while the test runs.
              textfileDir = nodes.machine.services.holochain-edgenode.metricsExporter.textfileDirectory;
              writeFixtures = pkgs.writeShellScript "write-fixture-textfiles" ''
                set -eu
                stamp=$(($(date +%s) + 3600))
                for name in workshop moss; do
                  sed -E "s/^(holochain_conductor_metrics_scrape_timestamp_seconds[{][^}]*[}]) .*/\1 $stamp/" \
                    ${fixtureTextfiles}/$name.prom > ${textfileDir}/.fixture-$name.tmp
                  mv ${textfileDir}/.fixture-$name.tmp ${textfileDir}/fixture-$name.prom
                done
              '';
              # The record names of the rule file this node runs.
              records =
                map (rule: rule.record)
                (builtins.head
                  (import ./modules/holochain-rules.nix {
                    interval = nodes.machine.services.holochain-grafana.scrapeInterval;
                    inherit (nodes.machine.services.holochain-grafana) states;
                  }).groups).rules;
            in ''
              import base64
              import json
              import re
              import shlex

              machine.wait_for_unit("grafana.service")
              machine.wait_for_unit("prometheus.service")
              machine.wait_for_open_port(3000)
              machine.wait_for_open_port(9090)
              machine.succeed("curl -sf http://localhost:3000/api/health")

              # NixOS 26.05 dropped Grafana's default secret key; the module
              # generates one at first boot, outside the store, and keeps it.
              key_stat = machine.succeed("stat -c '%a %U' /var/lib/grafana/secret_key").strip()
              assert key_stat == "400 grafana", key_stat
              key_before = machine.succeed("sha256sum /var/lib/grafana/secret_key")
              machine.succeed("systemctl restart grafana-secret-key.service grafana.service")
              machine.wait_for_open_port(3000)
              assert machine.succeed("sha256sum /var/lib/grafana/secret_key") == key_before, (
                  "the secret key was regenerated on restart"
              )

              # ---- criterion 4: the conductor's own series ----
              machine.wait_for_unit("holochain-conductor.service")
              machine.wait_for_unit("holochain-conductor-metrics.timer")
              machine.wait_for_unit("holochain-happ-installer.service")

              # The timer fires on its interval; the first file may not exist
              # yet when the conductor has only just come up.
              machine.wait_until_succeeds(
                  "curl -s localhost:9100/metrics | grep '^holochain_'", timeout=180
              )
              holochain_metrics = machine.succeed(
                  "curl -s localhost:9100/metrics | grep '^holochain_'"
              )
              machine.log("holochain series on /metrics:\n" + holochain_metrics)
              assert 'holochain_conductor_up{conductor="Holochain"} 1' in holochain_metrics, (
                  "the conductor answered dump-network-stats nowhere:\n" + holochain_metrics
              )

              # ---- criterion 3: the live target is up, the dead one down ----
              machine.wait_until_succeeds(
                  "curl -s localhost:9090/api/v1/targets"
                  " | jq -e '[.data.activeTargets[] | {(.labels.instance): .health}] | add"
                  " | .[\"127.0.0.1:9100\"] == \"up\" and .[\"${deadTarget}\"] == \"down\"'",
                  timeout=120,
              )
              targets = machine.succeed(
                  "curl -s localhost:9090/api/v1/targets"
                  " | jq -c '.data.activeTargets[] | {scrapeUrl, health, lastError}'"
              )
              machine.log("prometheus targets:\n" + targets)

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

              # ---- criterion 5: the four dashboards, the room screen at home ----
              def grafana(path):
                  return json.loads(machine.succeed(
                      "curl -sf -u admin:${grafanaTestPassword}"
                      f" 'http://localhost:3000{path}'"
                  ))


              # Exactly the four, and nothing else wearing their tag.
              def the_four(path):
                  uids = sorted(d["uid"] for d in grafana(path))
                  machine.log(f"{path}: " + json.dumps(uids))
                  return uids == ["holochain-fleet", "holochain-network", "holochain-node", "holochain-now"]


              tagged = sorted(d["uid"] for d in grafana("/api/search?tag=holochain"))
              assert the_four("/api/search?tag=holochain"), tagged
              # The same test on an answer Grafana gives with one short must fail.
              assert not the_four("/api/search?tag=holochain&limit=3")

              # Grafana's home page is the room screen. Grafana answers with
              # the dashboard itself, or with a redirect to it when the home
              # page is a saved preference.
              def is_room(answer):
                  uid = answer.get("dashboard", {}).get("uid")
                  machine.log(f"dashboard: uid {uid!r}, redirect {answer.get('redirectUri')!r}")
                  return uid == "holochain-now" or "/d/holochain-now" in answer.get("redirectUri", "")


              home = grafana("/api/dashboards/home")
              assert is_room(home), "the home page is not the room screen: " + json.dumps(home)[:500]
              # Another dashboard, in the same shape of answer, must not pass.
              assert not is_room(grafana("/api/dashboards/uid/holochain-fleet"))

              # A provisioned dashboard that Grafana cannot bind to a data
              # source renders empty panels, which a search hit would not show.
              datasource = machine.succeed(
                  "curl -s -u admin:${grafanaTestPassword}"
                  " http://localhost:3000/api/datasources/uid/holochain-prometheus"
              )
              machine.log("grafana datasource: " + datasource)
              assert '"type":"prometheus"' in datasource, datasource

              # Prometheus must hold the series the pages are built on, not
              # merely accept the queries.
              def prom_file(expr, name):
                  encoded = base64.b64encode(expr.encode()).decode()
                  machine.succeed(f"echo {encoded} | base64 -d > /tmp/{name}")
                  return f"/tmp/{name}"


              def prom_query(path):
                  return json.loads(machine.succeed(
                      f"curl -s --get localhost:9090/api/v1/query --data-urlencode query@{path}"
                  ))


              def wait_non_empty(expr, name, timeout=180):
                  path = prom_file(expr, name)
                  machine.wait_until_succeeds(
                      f"curl -s --get localhost:9090/api/v1/query --data-urlencode query@{path}"
                      " | jq -e '.status == \"success\" and (.data.result | length > 0)'",
                      timeout=timeout,
                  )
                  return prom_query(path)["data"]["result"]


              result = wait_non_empty(
                  'node_systemd_unit_state{name="holochain-conductor.service",state="active"} == 1',
                  "q-conductor-unit",
              )
              machine.log("conductor unit active: " + json.dumps(result))

              # The live conductor's own app: one DHT per role, each with a
              # name and none of them a key.
              dht_names = {
                  r["metric"]["network_label"]
                  for r in wait_non_empty('holochain_dht_info{app_id="dino-adventure"}', "q-dht-names")
              }
              machine.log("live DHTs: " + json.dumps(sorted(dht_names)))
              assert dht_names and all(n and "$" not in n and "uhC" not in n for n in dht_names), dht_names

              # The dashboards as Grafana serves them, after the module
              # rewrote them.
              served = {uid: grafana(f"/api/dashboards/uid/{uid}")["dashboard"] for uid in tagged}
              panels = {}
              for uid, dashboard in served.items():
                  panels[uid] = []
                  for panel in dashboard["panels"]:
                      panels[uid].append(panel)
                      panels[uid].extend(panel.get("panels", []))
                  machine.log(f"{uid}: " + ", ".join(p["title"] for p in panels[uid]))
              variables = {
                  uid: {v["name"]: v for v in dashboard["templating"]["list"]}
                  for uid, dashboard in served.items()
              }

              # The room constants, rewritten from the room option.
              room = {n: variables["holochain-now"][n]["current"]["value"] for n in ["room_app", "room_part", "room_label"]}
              machine.log("room constants: " + json.dumps(room))
              assert room == {
                  "room_app": "requests-and-offers",
                  "room_part": "requests_and_offers",
                  "room_label": "Requests & Offers",
              }, room

              # The node page's node variable, run the way Grafana runs
              # label_values(): both targets, by name, the dead one included.
              definition = variables["holochain-node"]["node"]["definition"]
              m = re.fullmatch(r"label_values\((.*),\s*(\w+)\)", definition)
              assert m, f"unexpected node variable definition: {definition}"
              selector_file = prom_file(m.group(1), "q-node-selector")
              nodes = json.loads(machine.succeed(
                  f"curl -s --get localhost:9090/api/v1/label/{m.group(2)}/values"
                  f" --data-urlencode match[]@{selector_file}"
              ))["data"]
              machine.log("node variable values: " + json.dumps(nodes))
              assert sorted(nodes) == ["machine", "unplugged"], nodes

              # What the states look like. A swapped colour or a lost word
              # would leave every query passing.
              def panel(uid, title):
                  # A collapsed row can share its title with the panel in it.
                  return next(p for p in panels[uid] if p["title"] == title and p["type"] != "row")


              def words(mappings):
                  return {
                      value: (option["text"], option["color"])
                      for m in mappings if m["type"] == "value"
                      for value, option in m["options"].items()
                  }


              def override(p, field, prop):
                  return next(
                      q["value"]
                      for o in p["fieldConfig"]["overrides"] if o["matcher"]["options"] == field
                      for q in o["properties"] if q["id"] == prop
                  )


              grey, amber = "#8e8e8e", "#EAB839"
              app_words = {
                  "0": ("Not running", "red"), "1": ("No fresh readings", "orange"),
                  "2": ("Lost contact", "red"), "3": ("No one else yet", grey),
                  "4": ("Catching up", amber), "5": ("In step", "green"),
              }
              node_words = {
                  "0": ("Unreachable", "red"), "1": ("Holochain not answering", "red"),
                  "2": ("A service is down", "red"), "3": ("No fresh readings", "orange"),
                  "4": ("Running", "green"), "5": ("No Holochain here", grey),
              }
              service_words = {
                  "0": ("Failed", "red"), "1": ("Stopped", "red"), "2": ("Not answering", "red"),
                  "3": ("No fresh readings", "orange"), "4": ("Starting", amber),
                  "5": ("Stopping", amber), "6": ("Running", "green"),
              }
              for uid, title in [("holochain-now", "Is each app working on each node?"),
                                 ("holochain-fleet", "Is each app in step on each node?")]:
                  assert words(panel(uid, title)["fieldConfig"]["defaults"]["mappings"]) == app_words, (uid, title)
              assert words(override(panel("holochain-node", "Is each app part connected, complete and recent?"), "State", "mappings")) == app_words
              assert words(panel("holochain-network", "Status on each node")["fieldConfig"]["defaults"]["mappings"]) == app_words
              assert words(panel("holochain-now", "Which machines are on?")["fieldConfig"]["defaults"]["mappings"]) == node_words
              assert words(override(panel("holochain-fleet", "Which node needs attention?"), "Status", "mappings")) == node_words
              assert words(panel("holochain-node", "Conductors")["fieldConfig"]["defaults"]["mappings"]) == {
                  "1": ("Not answering", "red"), "2": ("No fresh readings", "orange"), "3": ("Running", "green"),
              }
              assert words(panel("holochain-fleet", "Node status over time")["fieldConfig"]["defaults"]["mappings"]) == node_words
              # Both service tables read their states in the same words.
              for uid, title in [("holochain-fleet", "Which services are not running?"), ("holochain-node", "Is each service on this machine running?")]:
                  assert words(override(panel(uid, title), "State", "mappings")) == service_words, (uid, title)

              # ---- node names and the recording rules, over three conductors ----
              # Every target carries its node's name, and its site when it has one.
              target_labels = json.loads(machine.succeed(
                  "curl -s localhost:9090/api/v1/targets"
                  " | jq -c '[.data.activeTargets[] | {(.labels.instance): (.labels | {node, site})}] | add'"
              ))
              machine.log("target labels: " + json.dumps(target_labels))
              assert target_labels == {
                  "127.0.0.1:9100": {"node": "machine", "site": "CI"},
                  "${deadTarget}": {"node": "unplugged", "site": None},
              }, target_labels

              def wait_values(expr, name, want, key, timeout=180):
                  # Waits until the query answers exactly `want`, {key label: value}.
                  path = prom_file(expr, name)
                  want_json = json.dumps(want)
                  assert "'" not in want_json, want_json
                  machine.wait_until_succeeds(
                      f"curl -s --get localhost:9090/api/v1/query --data-urlencode query@{path}"
                      f" | jq -e --argjson want '{want_json}'"
                      f" '[.data.result[] | {{(.metric.{key} // \"\"): .value[1]}}] | add == $want'",
                      timeout=timeout,
                  )
                  machine.log(f"{expr}: {json.dumps(want)}")

              machine.succeed("${writeFixtures}")

              # node_exporter serves every series of the three files, with no
              # scrape error: the two fixtures declare their families exactly as
              # the live conductor's exporter does.
              fixture_dhts = 4 + 7
              wait_values('count(holochain_dht_peers{conductor=~"Workshop|Moss"})', "q-fixture-dhts", {"": str(fixture_dhts)}, "none")
              wait_values("count(holochain_dht_peers)", "q-all-dhts", {"": str(fixture_dhts + len(dht_names))}, "none")
              wait_values("max(node_textfile_scrape_error)", "q-scrape-error", {"": "0"}, "none")

              # Every rule of the file is loaded, has been evaluated, and has
              # not failed: a join that turns many-to-many on real series
              # fails the whole rule, with the reason in lastError.
              # Prometheus leaves lastError out of the reply when it is empty.
              records = json.loads('${builtins.toJSON records}')

              def rule_states():
                  groups = json.loads(machine.succeed("curl -s localhost:9090/api/v1/rules"))["data"]["groups"]
                  return [
                      (r["name"], r["health"], r.get("lastError", ""), r["lastEvaluation"])
                      for g in groups for r in g["rules"]
                  ]

              # Only an evaluation that started after the fixtures were
              # visible says anything about them.
              since = int(machine.succeed("date +%s").strip()) + 1
              try:
                  machine.wait_until_succeeds(
                      "curl -s localhost:9090/api/v1/rules"
                      f" | jq -e --argjson since {since} '[.data.groups[].rules[]"
                      " | select(.health != \"ok\" or (.lastError // \"\") != \"\""
                      " or (.lastEvaluation | sub(\"[.][0-9]+Z$\"; \"Z\") | fromdate) < $since)]"
                      " | length == 0'",
                      timeout=180,
                  )
              finally:
                  machine.log("rules: " + json.dumps(rule_states()))
              loaded = rule_states()
              assert sorted(r[0] for r in loaded) == sorted(records), (sorted(r[0] for r in loaded), records)
              for name, health, error, _ in loaded:
                  assert health == "ok" and error == "", (name, health, error)

              # Every conductor answers, but always-fails.service, which
              # overviewUnits adds to the watched services, has failed: the
              # node reads A service is down, and the dead target reads
              # Unreachable, each by its name.
              wait_values("holochain:node_state", "q-node-state", {"machine": "2", "unplugged": "0"}, "node")
              wait_values('max by (conductor) (holochain:conductor_state)', "q-conductor-state",
                          {"Holochain": "3", "Workshop": "3", "Moss": "3"}, "conductor")

              # The services of the machine by name, and nothing else: the ones
              # its modules installed, as the machine lists them, the two
              # overviewUnits adds, by their unit names, and the two fixture
              # conductors that no unit on the machine claims, the Moss one as
              # "Holochain conductor (Moss)". The live conductor is claimed by
              # its unit.
              wait_values('max by (service) (holochain:service_state{node="machine"})', "q-services", {
                  "Holochain conductor": "6", "App installer": "6", "Holochain readings (timer)": "6",
                  "Metrics database": "6", "Dashboards": "6", "Machine readings": "6", "Nix": "6",
                  "systemd-journald.service": "6", "always-fails.service": "0",
                  "Holochain conductor (Moss)": "6", "Holochain conductor (Workshop)": "6",
              }, "service")

              # The Moss node's shape: the connected chat and the group in step,
              # the chat nobody else opened alone and grey, not red.
              wait_values('max by (network_label) (holochain:dht_state:named{conductor="Moss"})', "q-moss-states", {
                  "Sensorica: Members and tools": "5", "Sensorica: Foyer": "5", "Sensorica: Shared assets": "5",
                  "General chat: Messages": "5", "General chat: Files": "5",
                  "Vines 1: Messages": "3", "Vines 1: Files": "3",
              }, "network_label")
              # The live app is alone on its network: No one else yet.
              wait_values('max by (network_label) (holochain:dht_state:named{conductor="Holochain"})', "q-live-states",
                          {n: "3" for n in dht_names}, "network_label")

              # In words: the two units that always fail, each by its name,
              # the watched one and the one no panel watches, and nothing else:
              # no disk, memory or heat problem on a healthy VM, and nothing
              # that would mean the readings or the names are broken.
              expected_problems = {"always-fails.service has failed", "fails-unwatched.service has failed"}
              machine.wait_until_succeeds(
                  "curl -s --get localhost:9090/api/v1/query"
                  " --data-urlencode 'query=count(holochain:node_problem{node=\"machine\", problem=~\".* has failed\"})'"
                  " | jq -e '.data.result[0].value[1] == \"2\"'",
                  timeout=120,
              )
              problems = {
                  r["metric"]["problem"]
                  for r in wait_non_empty('holochain:node_problem{node="machine"}', "q-problems")
              }
              machine.log("problems: " + json.dumps(sorted(problems)))
              assert problems == expected_problems, problems

              # ---- every panel of the four pages, through Grafana's own query API ----
              # With the three conductors present, each target goes to
              # /api/ds/query with its variables filled as Grafana fills them:
              # All for the multi-value ones, this node, the connected Moss
              # chat for the network page, the rewritten units and room
              # constants. Each must come back without an error and with at
              # least one frame holding a value. Three may be empty here and
              # must still not error: the two temperature panels, since QEMU
              # exposes no hwmon sensor, and "Same data everywhere", which
              # needs two nodes on one network (checks.dashboardQueries still
              # requires the rule it reads to be recorded). A query that
              # answers through an "or vector()" fallback answers here
              # whatever its left side reads; checks.dashboardQueries requires
              # every series its left side reads to be there.
              network = next(
                  r["metric"]["dna"]
                  for r in wait_non_empty(
                      'holochain_dht_info{conductor="Moss", network_label="General chat: Messages"}', "q-network"
                  )
              )
              machine.log("network page variable: " + network)


              def fill(expr):
                  for name, value in [
                      ("''${room_app}", room["room_app"]),
                      ("''${room_part}", room["room_part"]),
                      ("$network", network),
                      ("$node", "machine"),
                      ("$site", ".*"),
                      ("$conductor", ".*"),
                  ]:
                      expr = expr.replace(name, value)
                  assert "$" not in expr, f"unfilled variable in {expr}"
                  return expr


              answered = (
                  "(.results.A.error == null)"
                  " and ([.results.A.frames[]? | (.data.values // []) | length > 0 and (.[-1] | length > 0)] | any)"
              )


              def ds_query(expr, instant, name):
                  # The shell command that posts one query and prints the reply.
                  body = {
                      "from": "now-10m",
                      "to": "now",
                      "queries": [{
                          "refId": "A",
                          "datasource": {"type": "prometheus", "uid": "holochain-prometheus"},
                          "expr": expr,
                          "instant": instant,
                          "range": not instant,
                          "intervalMs": 15000,
                          "maxDataPoints": 200,
                      }],
                  }
                  encoded = base64.b64encode(json.dumps(body).encode()).decode()
                  machine.succeed(f"echo {encoded} | base64 -d > /tmp/{name}.json")
                  return (
                      "curl -s -u admin:${grafanaTestPassword} -H 'Content-Type: application/json'"
                      f" -X POST --data @/tmp/{name}.json http://localhost:3000/api/ds/query"
                  )


              # No sensor, but the collector that would read one runs.
              wait_non_empty('node_scrape_collector_success{collector="hwmon"} == 1', "q-hwmon")
              may_be_empty = {"Same data everywhere"}
              answered_labels, empty_allowed = [], []
              for uid in tagged:
                  for p in panels[uid]:
                      for target in p.get("targets", []):
                          expr = fill(target["expr"])
                          name = f"ds-{uid}-{p['id']}-{target['refId']}"
                          label = f"{uid} / {p['title']} [{target['refId']}]"
                          command = ds_query(expr, target.get("instant", False), name)
                          if "node_hwmon_temp_celsius" in expr or p["title"] in may_be_empty:
                              machine.succeed(f"{command} | jq -e '.results.A.error == null'")
                              machine.log(f"{label}: no error (may be empty here)")
                              empty_allowed.append(label)
                          else:
                              try:
                                  machine.wait_until_succeeds(f"{command} | jq -e '{answered}'", timeout=120)
                              except Exception:
                                  machine.log(f"{label} did not answer: " + machine.succeed(command)[:2000])
                                  raise
                              machine.log(f"{label}: answered")
                              answered_labels.append(label)
              # Counted apart, so the log says how many were required to
              # answer; the ones let off are exactly these three.
              machine.log(
                  f"{len(answered_labels)} panel queries answered through /api/ds/query;"
                  f" {len(empty_allowed)} only required not to error: " + json.dumps(empty_allowed)
              )
              assert sorted(empty_allowed) == [
                  "holochain-fleet / Hottest sensor [A]",
                  "holochain-network / Same data everywhere [A]",
                  "holochain-node / Temperatures [A]",
              ], empty_allowed
              assert len(answered_labels) >= 70, len(answered_labels)

              # The same test on a query that cannot answer must fail, or the
              # sweep above proves nothing.
              machine.fail(f"{ds_query('holochain:no_such_rule', True, 'ds-broken')} | jq -e '{answered}'")

              # A negative matcher keeps every series whatever the label is
              # called, so a misspelled label would pass the sweep. Each label
              # a query matches negatively has to exist on its metric.
              negative = set()
              for uid in tagged:
                  for p in panels[uid]:
                      for target in p.get("targets", []):
                          for metric, matchers in re.findall(r"([a-zA-Z_:][a-zA-Z0-9_:]*)\{([^}]*)\}", target["expr"]):
                              for label in re.findall(r"(\w+)\s*!(?:=|~)", matchers):
                                  negative.add((metric, label))
              machine.log("negatively matched labels: " + json.dumps(sorted(negative)))
              assert negative, "no negative matcher found; the parser is broken"
              for n, (metric, label) in enumerate(sorted(negative)):
                  wait_non_empty(f'count({metric}{{{label}!=""}})', f"q-negative-{n}")

              # node_exporter leaves mount units out unless told otherwise; the
              # modules tell it to, so a failed mount reaches the problem list.
              wait_non_empty('node_systemd_unit_state{name=~".+[.]mount"}', "q-mount-units")

              # The fixtures go, so what follows sees the live conductor alone.
              machine.succeed("rm ${textfileDir}/fixture-workshop.prom ${textfileDir}/fixture-moss.prom")
              wait_values("count(holochain_conductor_up)", "q-live-alone", {"": "1"}, "none")

              # ---- the conductor, failing in each of the ways the pages name ----
              def target_expr(uid, title, ref="A"):
                  return fill(next(t["expr"] for t in panel(uid, title)["targets"] if t["refId"] == ref))


              conductors = target_expr("holochain-node", "Conductors")
              problems_expr = target_expr("holochain-fleet", "What needs a human?")

              def wait_conductor(value, timeout):
                  wait_values(conductors, f"q-conductor-{value}", {"Holochain": str(value)}, "conductor", timeout=timeout)

              def wait_problem(sentence, timeout):
                  path = prom_file(problems_expr, "q-problem")
                  machine.wait_until_succeeds(
                      f"curl -s --get localhost:9090/api/v1/query --data-urlencode query@{path}"
                      f" | jq -e --arg p {shlex.quote(sentence)} 'any(.data.result[]; .metric.node == \"machine\" and .metric.problem == $p)'",
                      timeout=timeout,
                  )
                  machine.log(f"problem named: {sentence}")

              # The rule reads Not answering before it reads stale, so the
              # stale case comes first, while the last file still says up.
              # No fresh readings: nothing writes any more, and the last file stays.
              machine.succeed("systemctl stop holochain-conductor-metrics.timer")
              wait_conductor(2, 360)
              wait_problem("Holochain readings are over 90 s old", 60)

              # Not answering: the timer writes again, and says so.
              machine.succeed("systemctl stop holochain-conductor.service")
              machine.succeed("systemctl start holochain-conductor-metrics.timer")
              wait_conductor(1, 180)
              wait_problem("Holochain is not answering", 60)

              # A textfile node_exporter cannot parse drops every series in
              # it: the problem list says so, and the room screen's readings
              # tile reads 1e9, which its mapping shows as "No readings" in red
              # (checks.dashboardWords holds the mapping). The timer
              # stops first, or its next run would replace the file.
              machine.succeed("systemctl stop holochain-conductor-metrics.timer")
              machine.succeed(
                  "echo 'not a metric line' > /var/lib/prometheus-node-exporter-text-files/holochain-conductor.prom"
              )
              wait_problem("A metrics file could not be read (see the node_exporter log)", 120)
              wait_values(target_expr("holochain-now", "Are these readings current?"), "q-no-readings", {"": "1000000000"}, "none", timeout=120)

              # A dashboard Grafana could not provision leaves an error in its
              # journal and nothing else.
              journal = machine.succeed("journalctl -u grafana --no-pager")
              offenders = [
                  line
                  for line in journal.splitlines()
                  if "level=error" in line and "provisioning" in line
              ]
              assert not offenders, "grafana provisioning errors:\n" + "\n".join(offenders)
            '';
          };

          # The test sandbox has no network, so this asserts what the module
          # generates rather than a running container; the image is pulled and
          # run for real on the Builder's machine (see the PR body).
          vmTestWindtunnel = pkgs.testers.nixosTest {
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
          vmTestGateway = pkgs.testers.nixosTest {
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

          # Two 0.6 edgenodes find each other through a holochain-bootstrap
          # server with no internet, over its plain-HTTP relay.
          vmTestBootstrap = bootstrapTest {name = "holochain-bootstrap";};

          # Every service the enabled modules install, on the node page by
          # its name, derived from the configuration: with the bootstrap
          # server and the HTTP gateway, then without the server.
          vmTestServices = servicesTest {name = "holochain-services";};
          vmTestServices-noBootstrap = servicesTest {
            name = "holochain-services-no-bootstrap";
            bootstrap = false;
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
