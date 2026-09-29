# The admin plane of a fleet: Headscale, the self-hosted Tailscale
# coordination server the other machines log into (see
# `examples/sensorica-fleet/hosts/remote-access.nix` for the client side), and
# optionally Grafana under its own public name. Both sit behind nginx with
# Let's Encrypt; the router forwards TCP 80 (ACME) and 443 to this machine and
# nothing else. Holochain does not use any of it: its peers meet through their
# own bootstrap and relay servers. Relays stay on Tailscale's public DERP map,
# which only ever carries encrypted traffic.
#
# The public names are plain DNS records at whatever registrar holds the zone.
# When the site's IP is dynamic and the registrar has no usable update API, the
# optional drift check compares the public IPv4 with what the name resolves to
# and publishes the answer as a metric, so a change of IP shows up on the
# dashboards instead of as a fleet that silently stops reaching its server.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.admin-plane;
  hs = config.services.headscale;
  grafanaPort = config.services.grafana.settings.server.http_port;

  # What a browser sees at the bare Headscale name: a plain notice served with
  # 403, not Headscale's blank 200. Clients never ask for `/`; they use /key,
  # /ts2021 and /machine.
  privatePage = pkgs.writeTextDir "private.html" ''
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>Private server</title>
    <style>
      :root { color-scheme: light dark; }
      body { margin: 0; min-height: 100vh; display: grid; place-items: center;
             font: 16px/1.5 system-ui, sans-serif; background: Canvas; color: CanvasText; }
      main { max-width: 32rem; padding: 2rem; text-align: center; }
      h1 { font-size: 1.4rem; margin: 0 0 .5rem; }
      p { margin: 0; opacity: .75; }
    </style>
    </head>
    <body>
    <main>
    <h1>Private server</h1>
    <p>This address serves a private network. There is nothing to browse here.</p>
    </main>
    </body>
    </html>
  '';

  driftNames = [cfg.headscale.domain] ++ lib.optional (cfg.grafana.domain != null) cfg.grafana.domain;

  # One gauge per public name: 1 when the name resolves (at a public resolver,
  # not this machine's /etc/hosts pin) to the site's current public IPv4, 0 when
  # it does not, plus the time of the check. A failed lookup of the public IP
  # writes nothing new, so the file's age is the signal that the check itself
  # is broken.
  driftScript = pkgs.writeShellApplication {
    name = "admin-plane-dns-drift";
    runtimeInputs = [pkgs.curl pkgs.dnsutils pkgs.coreutils];
    text = ''
      out=${lib.escapeShellArg cfg.dnsDrift.textfileDirectory}/admin-plane-dns.prom
      ip=$(curl -4 -fsS --max-time 15 ${lib.escapeShellArg cfg.dnsDrift.ipEchoUrl})
      tmp=$(mktemp "$out.XXXXXX")
      {
        echo "# HELP admin_plane_dns_matches_public_ip 1 when the public name resolves to this site's public IPv4."
        echo "# TYPE admin_plane_dns_matches_public_ip gauge"
        for name in ${lib.escapeShellArgs driftNames}; do
          resolved=$(dig +short A "$name" @${lib.escapeShellArg cfg.dnsDrift.resolver} | tail -n1)
          match=0
          if [ "$resolved" = "$ip" ]; then match=1; fi
          echo "admin_plane_dns_matches_public_ip{name=\"$name\"} $match"
          if [ "$match" = 0 ]; then
            echo "admin-plane: $name resolves to '$resolved', the public IPv4 is $ip" >&2
          fi
        done
        echo "# HELP admin_plane_dns_check_timestamp_seconds When the DNS drift check last ran."
        echo "# TYPE admin_plane_dns_check_timestamp_seconds gauge"
        echo "admin_plane_dns_check_timestamp_seconds $(date +%s)"
      } > "$tmp"
      chmod 0644 "$tmp"
      mv "$tmp" "$out"
    '';
  };
in {
  options.services.admin-plane = {
    enable = lib.mkEnableOption "the fleet's admin plane: Headscale (and optionally Grafana) on public names behind nginx with ACME";

    acmeEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "ops@example.org";
      description = ''
        Contact address registered with Let's Encrypt for the account;
        `null` registers without one. It lands in the repository with the
        host's configuration, so use a shared operations address rather than
        a person's. The
        certificates are ordered when the configuration is switched, over port
        80, so the DNS records and the router's forwards have to exist before
        that switch; an order that fails leaves nginx on a self-signed
        placeholder until `systemctl restart acme-order-renew-<name>` succeeds.
      '';
    };

    headscale = {
      domain = lib.mkOption {
        type = lib.types.str;
        example = "hs.example.org";
        description = ''
          Public name the Tailscale clients log into
          (`tailscale up --login-server https://<domain>`). It is baked into
          every client's state: changing it later means re-joining every
          machine, so pick a name that can follow the server to another host.
        '';
      };

      baseDomain = lib.mkOption {
        type = lib.types.str;
        default = "tailnet.internal";
        example = "sensorica.internal";
        description = ''
          MagicDNS suffix: inside the tailnet machines answer as
          `<hostname>.<baseDomain>`. Headscale refuses to start when the
          public `domain` sits under it.
        '';
      };

      nameservers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["1.1.1.1" "9.9.9.9"];
        description = "Resolvers Headscale hands to the clients for every name outside the tailnet.";
      };
    };

    grafana.domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "grafana.example.org";
      description = ''
        When set, Grafana (from `holochain-grafana`) also answers on this
        public name over HTTPS, with secure cookies and its root URL rewritten
        to match. Its login page becomes the only gate, so set
        `services.holochain-grafana.adminPasswordFile` to a strong password
        before enabling this; anonymous access and sign-up stay off. `null`
        keeps Grafana on the LAN and the tailnet only.
      '';
    };

    dnsDrift = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Check every `interval` that the public names still resolve to this
          site's public IPv4, and publish `admin_plane_dns_matches_public_ip`
          through node_exporter's textfile collector. Meant for a site whose IP
          can change and whose registrar cannot be updated automatically; turn
          it off when a dynamic-DNS client keeps the records current.
        '';
      };

      textfileDirectory = lib.mkOption {
        type = lib.types.str;
        default = config.services.holochain-edgenode.metricsExporter.textfileDirectory or "/var/lib/prometheus-node-exporter-text";
        defaultText = lib.literalMD "the edgenode's `metricsExporter.textfileDirectory` when that module is imported, else `/var/lib/prometheus-node-exporter-text`";
        description = "Directory node_exporter's textfile collector reads; it must already exist (the edgenode's metrics exporter creates it). Pointing it elsewhere writes a file nobody scrapes, and a missing directory fails the check in the journal.";
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "15min";
        description = "How often the check runs, as a systemd time span.";
      };

      resolver = lib.mkOption {
        type = lib.types.str;
        default = "1.1.1.1";
        description = "Public resolver asked for the names. Never this machine's own resolver: the module pins the Headscale name to 127.0.0.1 locally.";
      };

      ipEchoUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://api.ipify.org";
        description = "URL that answers with the caller's public IPv4 as plain text.";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = !(lib.hasSuffix ".${cfg.headscale.baseDomain}" cfg.headscale.domain);
          message = "services.admin-plane: headscale.domain must not sit under headscale.baseDomain.";
        }
        {
          assertion = cfg.grafana.domain == null || config.services.grafana.enable;
          message = "services.admin-plane: grafana.domain is set but Grafana is not enabled (enable services.holochain-grafana).";
        }
      ];

      services.headscale = {
        enable = true;
        address = "127.0.0.1";
        port = 8080;
        settings = {
          server_url = "https://${cfg.headscale.domain}";
          dns = {
            magic_dns = true;
            base_domain = cfg.headscale.baseDomain;
            nameservers.global = cfg.headscale.nameservers;
          };
        };
      };

      services.nginx = {
        enable = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        virtualHosts.${cfg.headscale.domain} = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://${hs.address}:${toString hs.port}";
            proxyWebsockets = true;
          };
          locations."= /".extraConfig = ''
            error_page 403 /private.html;
            return 403;
          '';
          locations."= /private.html" = {
            root = privatePage;
            extraConfig = ''
              internal;
              add_header X-Robots-Tag "noindex, nofollow" always;
            '';
          };
        };
      };

      security.acme = {
        acceptTerms = true;
        defaults.email = lib.mkIf (cfg.acmeEmail != null) cfg.acmeEmail;
      };

      networking.firewall.allowedTCPPorts = [80 443];

      # This machine's own `tailscale up` reaches the server through local
      # nginx, so it never depends on the router looping the public IP back.
      networking.hosts."127.0.0.1" = [cfg.headscale.domain];

      # The CLI (`headscale nodes list`, `preauthkeys create`) is the admin
      # interface; it talks to the server over its unix socket.
      environment.systemPackages = [hs.package];
    }

    (lib.mkIf (cfg.grafana.domain != null) {
      services.grafana.settings = {
        # holochain-grafana sets `localhost` values for a LAN-only Grafana.
        server = {
          domain = lib.mkForce cfg.grafana.domain;
          root_url = lib.mkForce "https://${cfg.grafana.domain}/";
        };
        security.cookie_secure = true;
      };

      services.nginx.virtualHosts.${cfg.grafana.domain} = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString grafanaPort}";
          proxyWebsockets = true;
        };
      };
    })

    (lib.mkIf cfg.dnsDrift.enable {
      systemd.services.admin-plane-dns-drift = {
        description = "Check that the admin plane's public names still resolve to this site";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        # Root, because the textfile directory belongs to whichever service
        # created it (the edgenode's user on a fleet host); everything but
        # that directory is read-only to the unit.
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe driftScript;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          ReadWritePaths = [cfg.dnsDrift.textfileDirectory];
        };
      };
      systemd.timers.admin-plane-dns-drift = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = cfg.dnsDrift.interval;
        };
      };
    })
  ]);
}
