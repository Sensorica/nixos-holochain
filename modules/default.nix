# modules/default.nix — module aggregator
# Import this file to get all modules at once:
#   imports = [ nixos-holochain.nixosModules.default ];
{...}: {
  imports = [
    ./holochain-edgenode.nix
    ./holochain-grafana.nix
    ./holochain-windtunnel.nix
    ./holochain-http-gateway.nix
  ];
}
