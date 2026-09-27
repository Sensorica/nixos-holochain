# modules/sensorica-event-node.nix — the Sensorica workshop event profile
# (#33).
#
# Before this module existed, examples/sensorica-fleet and Soushi's private
# homelab (which rehearses the same workshop node by importing
# examples/sensorica-fleet/happs.nix by path) each repeated the Holochain
# line, the three hApp bundles and the network seed. Two copies drift; this
# is the one export both build from.
#
# Deliberately NOT part of `nixosModules.default` (modules/default.nix): the
# other four modules are generic capabilities, and importing `default` should
# never hand a consumer the Sensorica workshop's opinionated hApp set. Import
# this module explicitly, alongside `holochain-edgenode`, to opt into the
# event profile.
#
# It declares no options of its own: it only supplies `mkDefault` values for
# options `holochain-edgenode.nix` already declares (package, hcPackage,
# happs, installerTimeout, the two metrics enables). `mkDefault` on the whole
# `happs` attribute set still lets a host override a single leaf — one hApp's
# `networkSeed`, or `src`, or the timeout, or the package — with an ordinary
# assignment, because the module system pushes an outer `mkDefault` down to
# every leaf of a nested attribute set (`pushDownProperties`). A host that
# wants a different hApp set entirely reassigns `happs` as a whole, which
# beats the default the same way. `services.holochain-edgenode.enable` is
# left to the host: this module carries the workshop's content shape, not
# whether the service runs at all.
{
  lib,
  pkgs,
  inputs,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;

  # The 0.6 line (ADR-015): every hApp below has a 0.6 release and none has a
  # 0.7 one. Same inputs.holonix-0_6 the root flake's own `holochain-0_6` and
  # `hc-0_6` packages come from, so a consumer that follows this repository's
  # inputs cannot drift onto a different 0.6.3 than the one this repository's
  # own VM tests ran against.
  line = {
    holochain = inputs.holonix-0_6.packages.${system}.holochain;
    hc = inputs.holonix-0_6.packages.${system}.hc;
  };

  happs = import ./sensorica-happs.nix {
    inherit pkgs;
    inherit (line) hc;
  };

  # One seed for the whole event: it is what makes every node one DHT per app
  # rather than isolated ones, and keeps the event off the public networks
  # these apps otherwise share.
  networkSeed = "sensorica-workshop-2026";
in {
  config = {
    services.holochain-edgenode = {
      package = lib.mkDefault line.holochain;
      hcPackage = lib.mkDefault line.hc;

      metricsExporter.enable = lib.mkDefault true;
      conductorMetrics.enable = lib.mkDefault true;

      # Three apps compile their wasm one after another on first boot, and a
      # Holoport is not a fast machine (see examples/sensorica-fleet/README.md).
      installerTimeout = lib.mkDefault 900;

      happs = lib.mkDefault {
        hrea = {
          src = happs.hrea;
          inherit networkSeed;
        };
        kando = {
          src = happs.kando;
          inherit networkSeed;
        };
        requests-and-offers = {
          src = happs.requests-and-offers;
          inherit networkSeed;
        };
      };
    };
  };
}
