# modules/holochain-http-gateway.nix
#
# HTTP gateway in front of the conductor — translates REST/HTTP calls to
# Holochain app WebSocket calls. Useful for web clients that cannot speak raw WebSocket.
# TODO: implement once a canonical gateway binary is chosen (holochain-lair-proxy, etc.)
{ config, lib, pkgs, ... }:

let
  cfg = config.services.holochain-http-gateway;
in
{
  options.services.holochain-http-gateway = {
    enable = lib.mkEnableOption "HTTP gateway in front of the Holochain conductor";

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port the HTTP gateway listens on.";
    };

    conductorAppPort = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "App port of the local conductor to proxy to.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = [
      "holochain-http-gateway module is a placeholder — gateway binary not yet selected."
    ];
  };
}
