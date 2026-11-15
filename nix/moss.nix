{
  inputs,
  self,
  ...
}: let
  nixpkgs = inputs.nixpkgs;
in
  # Moss's always-online node (#28), on x86_64 only because that is the
  # one platform it has been run on. A module of its own so the condition
  # sits on these two definitions rather than on the attribute sets below.
  {
    perSystem = {
      pkgs,
      system,
      lib,
      ...
    }: let
      # The Moss page and the names program, checked without a VM.
      mossChecks = import ../tests/moss.nix {
        inherit pkgs;
        nixos-holochain = self;
        exporter = pkgs.callPackage ../packages/holochain-conductor-exporter.nix {
          hc = inputs.holonix-0_6.packages.${system}.hc;
        };
        dashboard = ../modules/dashboards-moss/sensorica-moss-node.json;
        namesJq = ../modules/moss-node-names.jq;
      };
      pilotChecks = import ../tests/pilot-node.nix {
        inherit pkgs;
        nixos-holochain = self;
        wdocker = self.packages.${system}.wdocker-0_16;
        bootstrapSrv = self.packages.${system}.bootstrap-srv-0_7_1;
      };
    in
      lib.mkIf (system == "x86_64-linux") {
        # wdocker on the Moss 0.15 line, with the Holochain 0.6.1 binary it
        # expects. docs/moss-node.md runs it by hand.
        packages.wdocker-0_15 = pkgs.callPackage ../packages/wdocker.nix {};

        # wdocker on the Moss 0.16 line, at the build the Moss pilot runs:
        # `@theweave/wdocker@next` with the patched Holochain 0.7.1
        # (`holochain-0.7.1-mdns.8`) its Moss ships (#166).
        packages.wdocker-0_16 = pkgs.callPackage ../packages/wdocker-0_16.nix {};

        # The bootstrap and relay server the Moss pilot points at, the
        # stock holochain-0.7.1 release asset Moss itself pins (#122).
        packages.bootstrap-srv-0_7_1 = pkgs.callPackage ../packages/bootstrap-srv-0_7_1.nix {};

        # The packaged wdocker brings up a throwaway conductor on NixOS
        # without nix-ld and without downloading a Holochain binary. The
        # VM has no network, so a download attempt would fail the test.
        # The daemon reads its password on stdin, the one entry point
        # that needs no TTY; joining a group needs an invite and is #28's.
        checks.vmTestWdocker = let
          wdocker = self.packages.${system}.wdocker-0_15;
          root = "/root/.local/share/wdocker/0.15.x";
        in
          pkgs.testers.nixosTest {
            name = "wdocker-smoke";
            nodes.machine = {
              # The conductor alone takes about 900 MB.
              virtualisation = {
                cores = 4;
                memorySize = 4096;
                diskSize = 8192;
              };
              environment.systemPackages = [wdocker];
            };
            testScript = ''
              import re

              machine.wait_for_unit("multi-user.target")
              machine.succeed(
                  "systemd-run --unit=wdaemon-smoke --setenv=HOME=/root"
                  " ${pkgs.runtimeShell} -c 'printf vmtest | ${wdocker}/bin/wdaemon smoke'"
              )
              machine.wait_until_succeeds(
                  "journalctl -u wdaemon-smoke --no-pager | grep -q 'Daemon ready.'",
                  timeout=300,
              )
              journal = machine.succeed("journalctl -u wdaemon-smoke --no-pager")
              assert "No holochain binary found" not in journal, journal

              # Nothing was fetched into wdocker's own bins directory.
              bins = machine.succeed("ls -A ${root}/bins").strip()
              assert bins == "", f"wdocker downloaded into bins: {bins}"

              # The conductor is the packaged binary, and it carries the
              # process name `wdocker stop` looks for. pgrep patterns stop
              # at the kernel's 15-character comm, hence no escaped dot.
              pid = machine.succeed("pgrep '^holochain-v0.6'").strip()
              exe = machine.succeed(f"readlink /proc/{pid}/exe").strip()
              assert exe == "${wdocker}/libexec/wdocker/holochain-v0.6.1-moss-0.15-wdocker", exe

              config = machine.succeed(
                  "cat ${root}/conductors/smoke/conductor/conductor-config.yaml"
              )
              admin = re.search(r"port: (\d+)", config)
              assert admin, f"no admin port in conductor-config.yaml:\n{config}"
              machine.wait_for_open_port(int(admin.group(1)))

              listing = machine.succeed("HOME=/root wdocker list")
              machine.log(listing)
              assert re.search(r"smoke\s.*running", listing), listing

              machine.succeed("HOME=/root wdocker stop smoke")
              machine.wait_until_fails(f"kill -0 {pid}", timeout=60)
            '';
          };

        # The Moss node as a service (nixosModules.holochain-moss-node):
        # systemd starts the daemon with no terminal, the password comes
        # from a credential, the node survives a restart, and its
        # readings reach node_exporter as conductor="Moss". Then the
        # same machine with the password file gone must not reach
        # "Daemon ready.": a daemon that starts without its password
        # proves nothing about the credential.
        checks.vmTestMossNode = let
          node = password: {
            imports = [
              self.nixosModules.holochain-edgenode
              self.nixosModules.holochain-moss-node
            ];
            virtualisation = {
              cores = 4;
              memorySize = 4096;
              diskSize = 8192;
            };
            services.holochain-edgenode = {
              enable = true;
              package = inputs.holonix-0_6.packages.${system}.holochain;
              hcPackage = inputs.holonix-0_6.packages.${system}.hc;
              metricsExporter.enable = true;
            };
            services.holochain-moss-node = {
              enable = true;
              name = "vmtest";
              passwordFile = "/etc/moss-node-password";
            };
            # "yes": the password; "empty": an empty file; "no": none.
            environment.etc = lib.mkIf (password != "no") {
              "moss-node-password" = {
                text =
                  if password == "yes"
                  then "vmtest"
                  else "";
                mode = "0400";
              };
            };
          };
        in
          pkgs.testers.nixosTest {
            name = "moss-node-service";
            nodes = {
              machine = node "yes";
              nopassword = node "no";
              emptypassword = node "empty";
            };
            testScript = ''
              machine.wait_for_unit("moss-node.service")
              machine.wait_until_succeeds(
                  "journalctl -u moss-node --no-pager | grep -q 'Daemon ready.'", timeout=300)
              user = machine.succeed("systemctl show moss-node -p User --value").strip()
              assert user == "moss-node", user
              machine.succeed("moss-node --help | grep -q 'join \"INVITE_LINK\"'")
              listing = machine.succeed("moss-node wdocker list")
              assert "vmtest" in listing and "running" in listing, listing

              machine.succeed("systemctl start moss-node-metrics.service")
              machine.wait_until_succeeds(
                  "grep -q 'holochain_conductor_up{conductor=\"Moss\"} 1' /var/lib/prometheus-node-exporter-text-files/moss-node.prom",
                  timeout=120)

              machine.succeed("systemctl restart moss-node")
              machine.wait_until_succeeds(
                  "test $(journalctl -u moss-node --no-pager | grep -c 'Daemon ready.') -ge 2", timeout=300)

              nopassword.wait_for_unit("multi-user.target")
              nopassword.sleep(20)
              journal = nopassword.succeed("journalctl -u moss-node --no-pager")
              assert "Daemon ready." not in journal, "the daemon started without its password"

              # An empty file is refused before wdaemon sees it, so no
              # conductor is created with an empty password.
              emptypassword.wait_until_succeeds(
                  "journalctl -u moss-node --no-pager | grep -q 'is empty; write the conductor password'", timeout=120)
              emptypassword.fail("ls /var/lib/moss-node/.local/share/wdocker/0.15.x/conductors/vmtest")
            '';
          };

        # The pilot's always-online node and the bootstrap and relay server
        # it uses (#166, #122): the services in one network, and the ACME
        # wiring evaluated (tests/pilot-node.nix).
        checks.vmTestPilotNode = pilotChecks.vm;
        checks.pilotNodeAcmeWiring = pilotChecks.acmeWiring;

        # The Moss page and the names program, without a VM (tests/moss.nix).
        checks.moss-dashboard = mossChecks.mossDashboard;
        checks.moss-names = mossChecks.mossNames;
      };
  }
