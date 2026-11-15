{
  inputs,
  self,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    shared,
    ...
  }: let
    nixpkgs = inputs.nixpkgs;
    inherit (shared) bootstrapTest servicesTest;
  in {
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
  };
}
