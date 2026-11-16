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
  }: {
    devShells.default = pkgs.mkShell {
      buildInputs = with pkgs; [nixos-rebuild colmena nil nixd alejandra mdbook];
    };
  };
}
