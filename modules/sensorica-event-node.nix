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
# happs, installerTimeout, the two metrics enables). A host overrides any one
# of them with an ordinary assignment (default priority beats `mkDefault`).
#
# `happs` is set leaf by leaf (`happs.hrea.src = mkDefault ...;`,
# `happs.hrea.networkSeed = mkDefault ...;`, one pair per hApp) rather than as
# one `happs = mkDefault {...};`: `attrsOf (submodule ...)` merges each hApp's
# fields as independent options, and a whole-set `mkDefault` does not survive
# a host overriding a sibling field (verified empirically: a host setting
# only `happs.hrea.networkSeed` left `happs.hrea.src` "accessed but has no
# value defined", since NixOS's module merge does not push an outer
# `mkDefault` recursively through a raw nested attribute set here). Per-leaf
# `mkDefault` has no such gap: each field stands on its own default,
# independent of what a host does to any other field.
#
# The same merge means a plain reassignment cannot trim the hApp set. `happs`
# is `attrsOf`, so a host writing `happs = { hrea = ...; };` is unioned with
# this profile's keys, and the per-leaf defaults still fill in kando and
# requests-and-offers. To drop one app, set `happs.<app>.installed = false;`
# (the installer then skips it and its bundle is never built). To replace the
# set entirely, write `happs = lib.mkForce { ... };`. `services.holochain-
# edgenode.enable` is left to the host: this module carries the workshop's
# content shape, not whether the service runs at all.
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

      happs = {
        hrea = {
          src = lib.mkDefault happs.hrea;
          networkSeed = lib.mkDefault networkSeed;
        };
        kando = {
          src = lib.mkDefault happs.kando;
          networkSeed = lib.mkDefault networkSeed;
        };
        requests-and-offers = {
          src = lib.mkDefault happs.requests-and-offers;
          networkSeed = lib.mkDefault networkSeed;
        };
      };
    };
  };
}
