# Called from nix/checks.nix with the per-system arguments of
# nix/shared.nix.
# Every exported nixosModule, imported into a minimal system beside
# holochain-edgenode (the companion modules read its options, which is how a
# consumer imports them), evaluates: its imports resolve and its options and
# services merge. Nothing is enabled and nothing is built. This is what a consumer does first, and on
# 2026-11-15 nixosModules.default stopped evaluating (an import pointing at a
# path that no longer existed) while every other check stayed green, because
# no check imported it.
{
  inputs,
  nixpkgs,
  pkgs,
  self,
  system,
  ...
}: let
  inherit (pkgs) lib;
  evalModule = name: module: let
    cfg =
      (nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.holochain-edgenode
          module
          {
            _module.args.inputs = inputs;
            fileSystems."/" = {
              device = "none";
              fsType = "ext4";
            };
            boot.loader.grub.enable = false;
            system.stateVersion = "26.05";
          }
        ];
      }).config;
  in
    # Forcing the service names merges every module the import pulls in.
    builtins.seq (builtins.length (builtins.attrNames cfg.systemd.services)) name;
  names = builtins.attrNames self.nixosModules;
  evaluated = lib.mapAttrsToList evalModule self.nixosModules;
in
  assert lib.assertMsg (names != []) "no nixosModules exported";
    pkgs.runCommand "nixos-modules-eval" {} ''
      printf '%s\n' ${lib.escapeShellArgs evaluated} > $out
    ''
