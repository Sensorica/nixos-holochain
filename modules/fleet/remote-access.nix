# modules/fleet/remote-access.nix
#
# Remote access for a fleet host (AD6): a Tailscale client logged into the
# fleet's own Headscale, the server half that `admin-plane` runs, so SSH,
# Grafana and `nixos-rebuild` reach the host from outside its LAN. Holochain
# does not use the tailnet; its peers meet through their own bootstrap and
# relay servers.
#
# Per host, once the Headscale server exists: write a pre-auth key from
# `headscale preauthkeys create` to `authKeyFile` (root-only), set `enable`,
# and rebuild. The module names no server of its own; the fleet sets
# `loginServer` once for all its hosts.
{
  config,
  lib,
  ...
}: let
  cfg = config.services.remote-access;
in {
  options.services.remote-access = {
    enable = lib.mkEnableOption "the Tailscale client, logged into the fleet's Headscale";

    loginServer = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://hs.example.org";
      description = "Headscale's public URL, as `tailscale up --login-server` takes it. Required when `enable` is set.";
    };

    authKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/secrets/headscale-authkey";
      description = ''
        A pre-auth key from `headscale preauthkeys create`, read once at the
        first connection. A path, so the key never enters the Nix store.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.loginServer != null;
        message = "services.remote-access.loginServer must name the fleet's Headscale (for example https://hs.example.org) when services.remote-access.enable is set.";
      }
    ];
    services.tailscale = {
      enable = true;
      authKeyFile = cfg.authKeyFile;
      extraUpFlags = [
        "--login-server=${toString cfg.loginServer}"
        "--hostname=${config.networking.hostName}"
      ];
    };
    # SSH and Grafana answer on the tailnet without opening them to the LAN.
    networking.firewall.trustedInterfaces = ["tailscale0"];
  };
}
