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
  in {
    devShells.default = pkgs.mkShell {
      buildInputs = with pkgs; [nixos-rebuild colmena nil nixd alejandra mdbook];
    };
  };
}
