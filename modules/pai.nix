# modules/pai.nix
#
# Optional: deploy a Personal AI Infrastructure (PAI) instance alongside the
# Holochain conductor. Intended for stewards who want AI-assisted edgenode management.
# See: https://github.com/danielmiessler/PAI
# TODO: implement once PAI has a NixOS-native packaging story.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.holochain-pai;
in
{
  options.services.holochain-pai = {
    enable = lib.mkEnableOption "PAI (Personal AI Infrastructure) alongside the edgenode";
  };

  config = lib.mkIf cfg.enable {
    warnings = [
      "holochain-pai module is a placeholder — PAI NixOS packaging is not yet available."
    ];
  };
}
