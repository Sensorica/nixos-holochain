{
  inputs,
  self,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    shared,
    optionsDocs,
    ...
  }: let
    inherit (shared) conductorExporter gatewayPkgs gatewayPkgs06 holonix06 holoportInstall onX86;
    inherit (optionsDocs) optionsDoc optionsDocHeader;
  in {
    packages = {
      holochain-0_6 = holonix06.holochain;
      hc-0_6 = holonix06.hc;

      # kitsune2-bootstrap-srv, bootstrap and iroh relay in one binary:
      # 0.4.1 from holonix main-0.6, 0.5.0 from main-0.7. The
      # holochain-bootstrap module defaults to the 0.6 one.
      bootstrap-srv-0_6 = holonix06.bootstrap-srv;
      bootstrap-srv = inputs.holonix.packages.${system}.bootstrap-srv;

      # One gateway build per Holochain line, so an operator can check
      # which binary a node would run without evaluating a whole system.
      # The module picks between them from the conductor's version.
      holochain-http-gateway = gatewayPkgs.callPackage ../packages/holochain-http-gateway.nix {line = "0.7";};
      holochain-http-gateway-0_6 = gatewayPkgs06.callPackage ../packages/holochain-http-gateway.nix {line = "0.6";};

      # The textfile exporter, one per Holochain line because the admin
      # call differs. A conductor that is not an edgenode's own (a Moss
      # node, say) runs the one of its line under its own name.
      holochain-conductor-exporter = conductorExporter;
      holochain-conductor-exporter-0_6 = conductorExporter.override {hc = holonix06.hc;};

      # The committed docs/module-options.md is a copy of this build.
      options-doc = pkgs.runCommand "module-options.md" {} ''
        cat ${optionsDocHeader} ${optionsDoc.optionsCommonMark} > $out
      '';

      # docs/deployment.md § "Installing on a Holoport (legacy BIOS)".
      # x86_64 only; a null name leaves the attribute out elsewhere.
      ${onX86 "holoport-install"} = holoportInstall;
    };
  };
}
