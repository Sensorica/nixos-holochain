{
  inputs,
  self,
  ...
}: let
  nixpkgs = inputs.nixpkgs;
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
  flake = {
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
}
