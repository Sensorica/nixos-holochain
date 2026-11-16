# The generated option reference (docs/module-options.md), moved from
# flake.nix (AD1). The package itself is wired in nix/packages.nix.
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
        # than dragging in the whole NixOS module set to document five
        # files' worth of options.
        {_module.check = false;}
        ../modules/holochain/holochain-edgenode.nix
        ../modules/fleet/holochain-grafana.nix
        ../modules/holochain/holochain-windtunnel.nix
        ../modules/holochain/holochain-http-gateway.nix
        ../modules/holochain/holochain-bootstrap.nix
        ../modules/fleet/admin-plane.nix
        ../modules/fleet/remote-access.nix
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
                path = pkgs.lib.removePrefix (toString ../. + "/") (toString decl);
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
  in {
    _module.args.optionsDocs = {inherit optionsEval optionsDoc optionsDocHeader;};
  };
}
