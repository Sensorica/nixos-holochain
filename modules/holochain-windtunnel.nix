# modules/holochain-windtunnel.nix
#
# Wind Tunnel scenario runner module — runs automated load/scenario tests against
# a live conductor and optionally exposes Prometheus metrics.
# TODO: implement once Wind Tunnel's service interface is stable.
{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.holochain-windtunnel;
in
{
  options.services.holochain-windtunnel = {
    enable = lib.mkEnableOption "Holochain Wind Tunnel scenario runner";

    conductorAdminPort = lib.mkOption {
      type = lib.types.port;
      default = 4444;
      description = "Admin port of the local conductor to target.";
    };

    metricsPort = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "Port to expose Prometheus metrics on.";
    };
  };

  config = lib.mkIf cfg.enable {
    # TODO: wire up Wind Tunnel binary once available via holonix or a dedicated input
    warnings = [
      "holochain-windtunnel module is a placeholder — implementation pending Wind Tunnel stable release."
    ];
  };
}
