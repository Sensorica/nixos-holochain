{
  inputs,
  self,
  ...
}: {
  flake = {
    # `nix flake init -t github:Sensorica/nixos-holochain#minimal` (or
    # `#fleet`) is the whole adoption story, so the templates point at the
    # published flake rather than a relative path: a copied tree has to
    # build from anywhere, not only from inside a checkout. The template
    # checks override the input to test the working tree.
    templates = rec {
      minimal = {
        path = ../templates/minimal;
        description = "A single Holochain edgenode: conductor, lair, hApp installer";
        welcomeText = ''
          # A Holochain edgenode

          - Paste your SSH public key into `configuration.nix`.
          - Replace `hardware-configuration.nix` with
            `nixos-generate-config --show-hardware-config` from the target machine.
          - `nix flake check --no-build`, then
            `sudo nixos-rebuild switch --flake .#edgenode`.

          README.md has the rest.
        '';
      };

      fleet = {
        path = ../templates/fleet;
        description = "Five Holochain edgenodes with Grafana on node-01, a colmena hive and a live ISO";
        welcomeText = ''
          # A Holochain edgenode fleet

          - Rename `hosts/node-0*` and the `hosts` list in `flake.nix` to your machines.
          - Paste your SSH public key into `hosts/common.nix`.
          - Replace each `hardware-configuration.nix` with real output from that machine.
          - `nix flake check --no-build`, then `nix develop` and
            `colmena apply --impure --on @all`.

          README.md has the rest.
        '';
      };

      default = minimal;
    };
  };
}
