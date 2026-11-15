# The per-system bindings the packages, checks and falsifiers share, moved
# from flake.nix's perSystem let (AD1). `args` is what every tests/*.nix
# file is called with; it is also the module argument `shared`.
{
  inputs,
  self,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    nixpkgs = inputs.nixpkgs;
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
    conductorExporter = pkgs.callPackage ../packages/holochain-conductor-exporter.nix {
      hc = inputs.holonix.packages.${system}.hc;
    };
    # The jq programs as the exporter runs them, with families.jq beside
    # them for `jq -L`.
    inherit (conductorExporter) jqLib;
    metricsChecks = import ../tests/metrics.nix {
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
    fixtureTextfiles = import ../tests/fixture-textfiles.nix {
      inherit pkgs jqLib;
      inherit (metricsChecks) names;
    };
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
    smokeTest = import ../tests/edgenode-smoke-vm.nix args;
    metricsTest = import ../tests/conductor-metrics-vm.nix args;
    happTest = import ../tests/happ-installer-vm.nix args;
    # ---- Holoport install (ADR-017) --------------------------------------
    #
    # Legacy BIOS means i386-pc GRUB and SeaBIOS, so the package and its
    # check exist on x86_64-linux only: an attribute named null is left out.
    onX86 = name:
      if system == "x86_64-linux"
      then name
      else null;
    #
    # scripts/holoport-install.sh is the whole install sequence; this pins
    # every tool it calls, so the stock NixOS ISO and the workshop ISO run
    # the same binaries the VM check does. `nix` and `udevadm` come from
    # the live system it runs on. x86_64 only: the BIOS half is i386-pc GRUB.
    holoportInstall = pkgs.writeShellApplication {
      name = "holoport-install";
      runtimeInputs = with pkgs; [
        coreutils
        dosfstools
        e2fsprogs
        gawk
        gnugrep
        grub2
        iproute2
        nixos-install
        parted
        util-linux
      ];
      text = builtins.readFile ../scripts/holoport-install.sh;
    };
    # The Sensorica event node as examples/sensorica-fleet builds it (same
    # modules, same host file, same 0.6 line and hApp bundles), on this
    # flake's nixpkgs rather than the fleet's own lock. Two additions: the
    # test driver's backdoor, which nixpkgs' installer tests also put into
    # the system they install, and a stand-in for the fleet's operator
    # desk (hosts/desk.nix), whose home-manager and plasma-manager inputs
    # this flake does not carry. The stand-in declares the two switches
    # the host file sets and keeps the Plasma session the desk turns on
    # for "plasma", so the installed closure still carries the desktop;
    # the desk's launchers and panel layout are not part of the rehearsal.
    holoportTarget = inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs;};
      modules = [
        self.nixosModules.holochain-edgenode
        self.nixosModules.holochain-grafana
        self.nixosModules.holochain-windtunnel
        # The line, hApps and seed, from the same export the fleet's
        # `fleetModules` import (#33).
        self.nixosModules.sensorica-event-node
        # sensorica-holoport-01 hosts the Sensorica Moss group's node.
        self.nixosModules.holochain-moss-node
        # ... and the fleet's admin plane (Headscale, public Grafana).
        # Offline in the test, its certificate orders fail; nothing here
        # asserts on them.
        self.nixosModules.admin-plane
        ({
          config,
          lib,
          ...
        }: {
          options.sensorica = {
            desktop = lib.mkOption {
              type = lib.types.enum ["plasma" "gnome" "none"];
              default = "plasma";
            };
            eventMode.enable = lib.mkEnableOption "the desk's event mode, not rehearsed here";
          };
          config = lib.mkIf (config.sensorica.desktop == "plasma") {
            services.desktopManager.plasma6.enable = true;
            services.displayManager.sddm.enable = true;
          };
        })
        ../examples/sensorica-fleet/hosts/sensorica-holoport-01/configuration.nix
        "${inputs.nixpkgs}/nixos/modules/testing/test-instrumentation.nix"
      ];
    };
    # The Holoport's disk as QEMU sees it: SATA behind AHCI, so it is
    # /dev/sda and the initrd reaches it through `ahci` from the fleet's
    # own hardware-configuration.nix, not through a virtio driver the real
    # box never loads. Both machines attach the same image; the test script
    # creates it and exports its path.
    holoportDisk = [
      "-device ahci,id=holoport-ahci"
      "-drive if=none,id=holoport-sda,format=qcow2,cache=writeback,werror=report,file=\"$HOLOPORT_DISK\""
      "-device ide-hd,drive=holoport-sda,bus=holoport-ahci.0,bootindex=1"
    ];
    bootstrapTest = import ../tests/bootstrap-vm.nix args;
    servicesTest = import ../tests/services-vm.nix args;

    args = {
      inherit pkgs system self inputs nixpkgs;
      inherit
        holonix06
        gatewayPkgs
        gatewayPkgs06
        conductorExporter
        metricsChecks
        monitor
        holochainRulesFile
        fixtureTextfiles
        dinoAdventureHapp
        kandoHapp
        edgenodeNode
        hcOnPath
        roomToWork
        grafanaTestPassword
        deadTarget
        on06
        adminCall
        smokeTest
        metricsTest
        happTest
        onX86
        holoportInstall
        holoportTarget
        holoportDisk
        bootstrapTest
        servicesTest
        jqLib
        ;
    };
  in {
    _module.args.shared = args;
  };
}
