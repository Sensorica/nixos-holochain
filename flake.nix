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
      in {
        packages = {
          holochain-0_6 = holonix06.holochain;
          hc-0_6 = holonix06.hc;

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

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [nixos-rebuild colmena nil nixd alejandra];
        };

        checks = {
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
          # node_exporter keeps both, and no name a dashboard shows is a hash;
          # then the fleet dashboard's conductor and DHT queries on both files
          # at once, as the homelab's one instance serves them.
          inherit (metricsChecks) metricsHelpAgreement metricsNameShape fleetDashboardQueries;

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
                scrapeTargets = ["127.0.0.1:9100" deadTarget];
                openFirewall = true;
                # Added to the default list rather than replacing it, both at
                # option-default priority, so the test sees the default units
                # and proves the option reaches the provisioned JSON.
                overviewUnits = pkgs.lib.mkOptionDefault ["systemd-journald.service" "always-fails.service"];
              };
              # A unit in the failed state, for the Overview to show as one.
              systemd.services.always-fails = {
                description = "A unit that always fails, for vmTestGrafana";
                wantedBy = ["multi-user.target"];
                script = "exit 1";
              };
            };
            testScript = ''
              import base64
              import json
              import re

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

              # ---- criterion 5: the dashboard is provisioned ----
              search = machine.succeed(
                  "curl -s -u admin:${grafanaTestPassword}"
                  " 'http://localhost:3000/api/search?query=Holochain'"
              )
              machine.log("grafana search: " + search)
              assert '"title":"Holochain Fleet"' in search, search
              assert '"uid":"holochain-fleet"' in search, search

              # A provisioned dashboard that Grafana cannot bind to a data
              # source renders empty panels, which a search hit would not show.
              datasource = machine.succeed(
                  "curl -s -u admin:${grafanaTestPassword}"
                  " http://localhost:3000/api/datasources/uid/holochain-prometheus"
              )
              machine.log("grafana datasource: " + datasource)
              assert '"type":"prometheus"' in datasource, datasource

              # ---- criterion 6: the overview answers "is everything up?" ----
              # Prometheus must hold the series the Overview row is built on,
              # not merely accept the queries.
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
              result = wait_non_empty(
                  'node_filesystem_size_bytes{mountpoint="/", fstype!~"tmpfs|ramfs|overlay|squashfs"} > 0',
                  "q-root-fs",
              )
              machine.log("root filesystem: " + json.dumps(result))

              # The dashboard as Grafana serves it, after the module rewrote it.
              served = json.loads(machine.succeed(
                  "curl -s -u admin:${grafanaTestPassword}"
                  " http://localhost:3000/api/dashboards/uid/holochain-fleet"
              ))["dashboard"]
              panels = []
              for panel in served["panels"]:
                  panels.append(panel)
                  panels.extend(panel.get("panels", []))
              titles = {p["title"] for p in panels}
              machine.log("provisioned panels: " + ", ".join(sorted(titles)))
              for title in [
                  "Overview", "Fleet status", "Services",
                  "Holochain", "Conductors up", "Conductor peers",
                  "Conductor network throughput", "Conductor metrics age",
                  "Conductor messages", "Blocked messages",
                  "DHT peers", "DHT ops held here vs best peer",
                  "DHT seconds since last gossip",
                  "Host health", "CPU busy", "Memory used", "Load average",
                  "Disk space used", "Disk IO", "Temperatures",
                  "Host network throughput", "Pressure",
              ]:
                  assert title in titles, f"panel {title!r} missing: {sorted(titles)}"

              variables = {v["name"]: v for v in served["templating"]["list"]}
              units = variables["units"]["current"]["value"]
              machine.log("units variable default: " + units)
              for unit in ["holochain-conductor.service", "systemd-journald.service"]:
                  assert unit in units.split("|"), f"{unit} not in the units default: {units}"

              # The instance variable's own definition, run the way Grafana
              # runs label_values(): the label's values over the selector.
              # Both targets have an up series, the dead one included.
              definition = variables["instance"]["definition"]
              m = re.fullmatch(r"label_values\((.*),\s*(\w+)\)", definition)
              assert m, f"unexpected instance variable definition: {definition}"
              selector_file = prom_file(m.group(1), "q-instance-selector")
              instances = json.loads(machine.succeed(
                  f"curl -s --get localhost:9090/api/v1/label/{m.group(2)}/values"
                  f" --data-urlencode match[]@{selector_file}"
              ))["data"]
              machine.log("instance variable values: " + json.dumps(instances))
              assert sorted(instances) == ["127.0.0.1:9100", "${deadTarget}"], instances

              # Every query on the dashboard, with its variables filled in the
              # way Grafana fills them for "All", has to be valid PromQL over
              # series that exist here, and has to answer for the live node
              # alone too, its name escaped the way a regex match needs it.
              # node_hwmon_temp_celsius is the one series a VM has nothing
              # for: QEMU exposes no hwmon sensor. Those queries only have to
              # be valid, and the collector that would feed them has to run.
              live = "127\\\\.0\\\\.0\\\\.1:9100"
              hwmon = wait_non_empty('node_scrape_collector_success{collector="hwmon"} == 1', "q-hwmon")
              machine.log("hwmon collector: " + json.dumps(hwmon))

              def fill(expr, instance):
                  return expr.replace("''${units:raw}", units).replace("$instance", instance)

              exprs = []
              for panel in panels:
                  for n, target in enumerate(panel.get("targets", [])):
                      exprs.append((panel, target, n))
              for panel, target, n in exprs:
                  for scope, instance in [("all", ".*"), ("live", live)]:
                      expr = fill(target["expr"], instance)
                      assert "$" not in expr, f"unsubstituted variable in {expr}"
                      name = f"q-panel-{panel['id']}-{n}-{scope}"
                      label = f"{panel['title']} [{target['refId']}] ({scope})"
                      if "node_hwmon_temp_celsius" in expr:
                          reply = prom_query(prom_file(expr, name))
                          assert reply["status"] == "success", f"{label}: {reply}"
                          machine.log(f"{label}: {len(reply['data']['result'])} series (none expected in a VM)")
                      else:
                          result = wait_non_empty(expr, name)
                          machine.log(f"{label}: {len(result)} series")

              # A negative matcher keeps every series whatever the label is
              # called, so a misspelled label would pass the loop above. Each
              # label a query matches negatively has to exist on its metric.
              negative = set()
              for panel, target, n in exprs:
                  for metric, matchers in re.findall(r"([a-zA-Z_:][a-zA-Z0-9_:]*)\{([^}]*)\}", target["expr"]):
                      for label in re.findall(r"(\w+)\s*!(?:=|~)", matchers):
                          negative.add((metric, label))
              machine.log("negatively matched labels: " + json.dumps(sorted(negative)))
              assert negative, "no negative matcher found; the parser is broken"
              for n, (metric, label) in enumerate(sorted(negative)):
                  wait_non_empty(f'count({metric}{{{label}!=""}})', f"q-negative-{n}")

              # node_exporter leaves mount units out unless told otherwise; the
              # modules tell it to, so a failed mount reaches Failed units.
              wait_non_empty('node_systemd_unit_state{name=~".+[.]mount"}', "q-mount-units")

              def by_instance(expr, name):
                  return {
                      r["metric"].get("instance"): r["value"][1]
                      for r in prom_query(prom_file(expr, name))["data"]["result"]
                  }

              def target_expr(title, ref):
                  return fill(next(
                      t["expr"] for p in panels if p["title"] == title for t in p["targets"] if t["refId"] == ref
                  ), ".*")

              # The Services panel's own query, in this node's terms: every
              # listed unit active, the failing one failed, and the dead
              # target a row of its own.
              services_expr = prom_file(target_expr("Services", "A"), "q-services")
              machine.wait_until_succeeds(
                  f"curl -s --get localhost:9090/api/v1/query --data-urlencode query@{services_expr}"
                  " | jq -e 'any(.data.result[]; .metric.name == \"always-fails.service\" and .value[1] == \"3\")'",
                  timeout=120,
              )
              services = {
                  (r["metric"]["instance"], r["metric"]["name"]): r["value"][1]
                  for r in prom_query(services_expr)["data"]["result"]
              }
              machine.log("services: " + json.dumps({f"{i} {n}": v for (i, n), v in sorted(services.items())}))
              for unit in [
                  "holochain-conductor.service", "holochain-conductor-metrics.timer",
                  "prometheus.service", "prometheus-node-exporter.service",
                  "grafana.service", "nix-daemon.socket", "systemd-journald.service",
              ]:
                  assert services.get(("127.0.0.1:9100", unit)) == "1", f"{unit} not active on the Services panel: {services}"
              assert services.get(("127.0.0.1:9100", "always-fails.service")) == "3", services
              assert services.get(("${deadTarget}", "node unreachable")) == "4", services
              assert not any(i == "${deadTarget}" and n != "node unreachable" for i, n in services), services

              # Fleet status in the same terms.
              node = by_instance(target_expr("Fleet status", "A"), "q-fleet-node")
              assert node == {"127.0.0.1:9100": "1", "${deadTarget}": "0"}, node
              failed = by_instance(target_expr("Fleet status", "D"), "q-fleet-failed")
              assert int(failed["127.0.0.1:9100"]) >= 1, failed
              conductor_expr = target_expr("Fleet status", "C")
              conductor = by_instance(conductor_expr, "q-fleet-conductor")
              assert conductor == {"127.0.0.1:9100": "1", "${deadTarget}": "5"}, conductor
              assert target_expr("Conductors up", "A") == conductor_expr, "Conductors up and Fleet status disagree"
              apps = by_instance(target_expr("Fleet status", "I"), "q-fleet-apps")
              assert apps == {"127.0.0.1:9100": "1"}, apps

              # The per-DHT panels in this node's terms: one line per DHT of
              # the one app, each named by its network_label and never by a
              # key, and a node alone on its network has no peer and has never
              # gossiped.
              def by_dht(title, ref, name):
                  return {
                      r["metric"]["network_label"]: r["value"][1]
                      for r in prom_query(prom_file(target_expr(title, ref), name))["data"]["result"]
                  }

              dht_names = {
                  r["metric"]["network_label"]
                  for r in prom_query(prom_file(
                      'holochain_dht_info{app_id="dino-adventure"}', "q-dht-names"
                  ))["data"]["result"]
              }
              dht_peers = by_dht("DHT peers", "A", "q-dht-peers")
              machine.log("DHT peers: " + json.dumps(dht_peers))
              assert dht_peers and dht_peers.keys() == dht_names, (dht_peers, dht_names)
              assert all(n and "$" not in n and "uhC" not in n for n in dht_names), dht_names
              assert set(dht_peers.values()) == {"0"}, dht_peers
              gossip = by_dht("DHT seconds since last gossip", "A", "q-dht-gossip")
              assert gossip.keys() == dht_peers.keys() and set(gossip.values()) == {"-1"}, gossip
              held = by_dht("DHT ops held here vs best peer", "A", "q-dht-held")
              best = by_dht("DHT ops held here vs best peer", "B", "q-dht-best")
              machine.log(f"DHT ops held here: {held}; best peer: {best}")
              assert held.keys() == dht_peers.keys() and set(best.values()) == {"0"}, best

              # What those numbers look like. A swapped colour or a lost
              # mapping would leave every query above passing.
              def mapping(panel_title, field=None):
                  panel = next(p for p in panels if p["title"] == panel_title)
                  if field is None:
                      found = panel["fieldConfig"]["defaults"]["mappings"]
                  else:
                      found = next(
                          prop["value"]
                          for o in panel["fieldConfig"]["overrides"]
                          if o["matcher"]["options"] == field
                          for prop in o["properties"]
                          if prop["id"] == "mappings"
                      )
                  return {
                      value: (option["text"], option["color"])
                      for m in found if m["type"] == "value"
                      for value, option in m["options"].items()
                  }

              conductor_states = {
                  "0": ("down", "red"), "1": ("up", "green"),
                  "2": ("stale, was down", "orange"), "3": ("stale, was up", "orange"),
                  "4": ("textfile error", "red"), "5": ("unknown", "text"),
              }
              assert mapping("Fleet status", "Conductor") == conductor_states, mapping("Fleet status", "Conductor")
              assert mapping("Conductors up") == conductor_states, mapping("Conductors up")
              assert mapping("Fleet status", "Node") == {"0": ("down", "red"), "1": ("up", "green")}
              assert mapping("DHT seconds since last gossip") == {"-1": ("never", "orange")}, mapping("DHT seconds since last gossip")
              assert mapping("Services") == {
                  "0": ("inactive", "orange"), "1": ("active", "green"),
                  "2": ("starting or stopping", "yellow"), "3": ("failed", "red"),
                  "4": ("unreachable", "red"),
              }, mapping("Services")

              # ---- the conductor, failing in each of the ways the Overview names ----
              def wait_conductor(value, timeout):
                  path = prom_file(conductor_expr, f"q-conductor-{value}")
                  machine.wait_until_succeeds(
                      f"curl -s --get localhost:9090/api/v1/query --data-urlencode query@{path}"
                      f" | jq -e 'any(.data.result[]; .metric.instance == \"127.0.0.1:9100\" and .value[1] == \"{value}\")'",
                      timeout=timeout,
                  )
                  machine.log(f"conductor state {value} ({conductor_states[str(value)][0]}) reached")

              # Down: the timer still writes, and says so.
              machine.succeed("systemctl stop holochain-conductor.service")
              wait_conductor(0, 180)

              # Stale: nothing writes any more, and the last file stays.
              machine.succeed("systemctl stop holochain-conductor-metrics.timer")
              wait_conductor(2, 360)

              # A textfile node_exporter cannot parse drops every series in it.
              machine.succeed(
                  "echo 'not a metric line' > /var/lib/prometheus-node-exporter-text-files/holochain-conductor.prom"
              )
              wait_conductor(4, 120)

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
