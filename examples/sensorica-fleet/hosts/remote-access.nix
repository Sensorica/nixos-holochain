# Remote access: each Holoport joins Sensorica's own tailnet, coordinated by
# Headscale at `sensorica.remoteAccess.loginServer`, so SSH, Grafana and
# `rebuild` reach it from outside the lab. Off until that server exists; then
# per host: write a Headscale pre-auth key to `authKeyFile` (root-only), flip
# `sensorica.remoteAccess.enable`, run `rebuild`. Holochain does not use the
# tailnet; its peers meet through their own bootstrap and relay servers.
{
  config,
  lib,
  ...
}: let
  cfg = config.sensorica.remoteAccess;
in {
  options.sensorica.remoteAccess = {
    enable = lib.mkEnableOption "the Tailscale client, logged into Sensorica's Headscale";

    loginServer = lib.mkOption {
      type = lib.types.str;
      default = "https://hs.sensorica.co";
      description = "Headscale's public URL, as `tailscale up --login-server` takes it.";
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
    services.tailscale = {
      enable = true;
      authKeyFile = cfg.authKeyFile;
      extraUpFlags = [
        "--login-server=${cfg.loginServer}"
        "--hostname=${config.networking.hostName}"
      ];
    };
    # SSH and Grafana answer on the tailnet without opening them to the lab.
    networking.firewall.trustedInterfaces = ["tailscale0"];
  };
}
