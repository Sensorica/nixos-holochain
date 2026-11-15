{
  inputs,
  self,
  ...
}:
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
    mossArgs = {inherit inputs lib pkgs self system;};
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

      checks.vmTestWdocker = import ../tests/wdocker-vm.nix mossArgs;

      checks.vmTestMossNode = import ../tests/moss-node-vm.nix mossArgs;

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
