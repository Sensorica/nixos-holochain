# Moved verbatim from flake.nix (AD1); called from nix/checks.nix with the
# shared per-system arguments of nix/shared.nix.
# The edgenode declares the Holochain Foundation cache by default, and
# the option really turns it off (#26). Evaluation only: a host that
# forgets the cache compiles Holochain from source on its first switch.
{
  inputs,
  nixpkgs,
  pkgs,
  self,
  system,
  ...
}: let
  eval = extra:
    (nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        self.nixosModules.holochain-edgenode
        {
          _module.args.inputs = inputs;
          services.holochain-edgenode.enable = true;
          fileSystems."/".device = "none";
          boot.loader.grub.enable = false;
          system.stateVersion = "26.05";
        }
        extra
      ];
    }).config.nix.settings;
  on = eval {};
  off = eval {services.holochain-edgenode.binaryCache.enable = false;};
  has = st:
    builtins.elem "https://holochain-ci.cachix.org" (st.extra-substituters or [])
    && builtins.elem "holochain-ci.cachix.org-1:5IUSkZc0aoRS53rfkvH9Kid40NpyjwCMCzwRTXy+QN8=" (st.extra-trusted-public-keys or []);
in
  assert has on;
  assert !(has off);
    pkgs.runCommand "edgenode-binary-cache" {} "echo on=${builtins.toJSON (has on)} off=${builtins.toJSON (has off)} > $out"
