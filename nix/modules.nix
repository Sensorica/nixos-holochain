{
  inputs,
  self,
  ...
}: {
  flake = {
    # Reusable modules for downstream consumers.
    # The Sensorica fleet that exercises them lives in examples/sensorica-fleet.
    nixosModules = let
      # The bootstrap server's package comes from this flake rather than
      # from the consumer's `inputs`, which need not carry a holonix 0.6
      # input at all. The module file itself declares no default, so this
      # wrapper is what fills it.
      bootstrapPackage = {
        lib,
        pkgs,
        ...
      }: {
        services.holochain-bootstrap.package =
          lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.bootstrap-srv-0_6;
      };
    in {
      holochain-edgenode = ../modules/holochain/holochain-edgenode.nix;
      holochain-windtunnel = ../modules/holochain/holochain-windtunnel.nix;
      holochain-http-gateway = ../modules/holochain/holochain-http-gateway.nix;
      holochain-grafana = ../modules/fleet/holochain-grafana.nix;
      holochain-bootstrap = {
        imports = [../modules/holochain/holochain-bootstrap.nix bootstrapPackage];
      };
      default = {
        imports = [../modules/holochain bootstrapPackage];
      };

      # The fleet's admin plane: Headscale and optionally a public
      # Grafana behind nginx with ACME. Not part of `default`: one machine
      # per fleet runs it, and it opens ports 80 and 443.
      admin-plane = ../modules/fleet/admin-plane.nix;

      # The client half of the admin plane: a Tailscale client logged into
      # the fleet's Headscale (AD6). Not part of `default`: a fleet turns it
      # on where it wants remote access, and names its server once.
      remote-access = ../modules/fleet/remote-access.nix;

      # The Sensorica workshop event profile (#33): package, hApps and
      # network seed for the workshop, layered on top of
      # `holochain-edgenode`. Not part of `default` on purpose; see the
      # comment at the top of the module.
      sensorica-event-node = ../modules/sensorica-event-node.nix;

      # A Moss always-online node as a service, with its readings and page
      # (#28). Not part of `default`: it runs a second conductor. The
      # wdocker package comes from this flake, as the bootstrap server's does.
      holochain-moss-node = {
        imports = [
          ../modules/moss/holochain-moss-node.nix
          ({
            lib,
            pkgs,
            ...
          }: {
            services.holochain-moss-node.package =
              lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.wdocker-0_15;
          })
        ];
      };
    };
  };
}
