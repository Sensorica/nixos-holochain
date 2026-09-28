# modules/holochain-bootstrap.nix
#
# The Kitsune2 bootstrap server as a NixOS service. One binary,
# `kitsune2-bootstrap-srv`, serves both peer discovery (`/bootstrap/{space}`)
# and the iroh relay (`/relay`) on one HTTP port, plus QUIC address discovery
# on a UDP port. Holonix builds it as the package `bootstrap-srv` on both
# Holochain lines (kitsune2 0.4.1 on main-0.6, 0.5.0 on main-0.7); upstream
# documents only a container, and no NixOS module existed for it.
#
# Every flag below was read from the binary's own `--help` and from
# kitsune2 v0.4.1 `crates/bootstrap_srv/src/bin/kitsune2-bootstrap-srv.rs`.
#
# The server keeps its state in tempfiles (`crates/bootstrap_srv/src/store.rs`),
# which is why the unit has no state directory at all: agent infos live in the
# unit's private /tmp and vanish with it. Conductors re-publish their agent
# info on a timer, so a restarted server refills itself within minutes.
{
  config,
  lib,
  ...
}: let
  cfg = config.services.holochain-bootstrap;

  tls = cfg.tlsCertFile != null;

  args =
    ["--production"]
    ++ lib.concatMap (addr: ["--listen" "${addr}:${toString cfg.port}"]) cfg.listenAddresses
    ++ ["--quic-bind-addr" "${cfg.quicAddress}:${toString cfg.quicPort}"]
    # The files are handed over as systemd credentials, so the dynamic user
    # reads a private copy and never needs access to the originals. `%d` is
    # the unit's credentials directory.
    ++ lib.optionals tls ["--tls-cert" "%d/tls-cert" "--tls-key" "%d/tls-key"]
    ++ lib.optionals (cfg.workerThreads != null) ["--worker-thread-count" (toString cfg.workerThreads)]
    ++ cfg.extraArgs;
in {
  options.services.holochain-bootstrap = {
    enable = lib.mkEnableOption ''
      the Kitsune2 bootstrap and relay server (`kitsune2-bootstrap-srv`).

      One process serves peer discovery at `/bootstrap/{space}` and an iroh
      relay at `/relay` on the same port. Point conductors at it with
      `services.holochain-edgenode.bootstrapUrl = "http(s)://<host>:<port>"`
      and `relayUrl = "http(s)://<host>:<port>/relay"`.

      The relay is open: it has no authentication by default, so anyone who
      can reach the port can relay traffic through it. Keep it on a LAN or
      behind a firewall unless that is what you want. Its state is ephemeral
      and cannot be shared between instances, so run one server per network,
      not several behind a load balancer
    '';

    package = lib.mkOption {
      type = lib.types.package;
      defaultText = lib.literalExpression "nixos-holochain.packages.\${system}.bootstrap-srv-0_6";
      description = ''
        The `kitsune2-bootstrap-srv` package. The flake's module defaults it to
        the holonix main-0.6 build (kitsune2 0.4.1), the line the Sensorica
        fleet runs. A 0.7 network takes `nixos-holochain.packages.''${system}.bootstrap-srv`
        instead (kitsune2 0.5.0): keep the server on the same line as the
        conductors that use it.
      '';
    };

    listenAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["[::]"];
      example = ["192.168.1.10"];
      description = ''
        Addresses the HTTP server binds, each on `port`. IPv6 addresses go in
        brackets. The default `[::]` is dual-stack on Linux and accepts IPv4
        as well; on a host with IPv6 disabled, use `0.0.0.0`.

        Do not list both `0.0.0.0` and `[::]`, although that is the server's
        own production default. On Linux the second bind fails with "address
        in use", and the 0.4.1 server does not exit on a failed bind: it logs
        nothing, listens on nothing and stays up, so systemd reports the unit
        active. Seen in this repository's VM test, not guessed.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = ''
        TCP port for bootstrap and relay, over HTTPS when a certificate is
        configured and plain HTTP otherwise. The unit holds
        `CAP_NET_BIND_SERVICE` so a port below 1024 works without root.
      '';
    };

    quicAddress = lib.mkOption {
      type = lib.types.str;
      default = "[::]";
      description = ''
        Address the QUIC address discovery (QAD) endpoint binds, which lets
        iroh clients learn their public address. On Linux `[::]` also accepts
        IPv4.
      '';
    };

    quicPort = lib.mkOption {
      type = lib.types.port;
      default = 7842;
      description = "UDP port for QUIC address discovery; 7842 is iroh's default.";
    };

    tlsCertFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/lib/acme/bootstrap.example.org/fullchain.pem";
      description = ''
        PEM certificate for HTTPS and for QUIC. A path as a string, read at
        service start through systemd's `LoadCredential`, so it never enters
        the Nix store and may be readable by root only. Set it together with
        `tlsKeyFile`.

        Without it the server speaks plain HTTP, and QUIC uses a self-signed
        certificate it generates at start. That is enough for a LAN of
        edgenodes, which then need
        `services.holochain-edgenode.relayAllowPlainText = true`. It is not
        enough for a packaged Moss desktop: Moss enables plain-text relays only
        in development builds, so a laptop running stock Moss needs this server
        on HTTPS with a certificate it trusts.

        The certificate is read once, at start: restart the unit after a
        renewal.
      '';
    };

    tlsKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/lib/acme/bootstrap.example.org/key.pem";
      description = "PEM private key matching `tlsCertFile`, loaded the same way.";
    };

    workerThreads = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = ''
        Worker threads for the HTTP server. `null` keeps the server's
        production default, four per CPU. The workers block on file IO, which
        is why the default exceeds the core count.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "info";
      example = "info,kitsune2_bootstrap_srv=debug";
      description = ''
        `RUST_LOG` filter for the server. Its built-in default is `debug`,
        which logs every request to the journal.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["--max-entries-per-space" "64" "--allowed-origins" "https://example.org"];
      description = "Further `kitsune2-bootstrap-srv` flags, appended as given.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open `port` on TCP and `quicPort` on UDP. Conductors on other machines
        cannot reach the server without this or an equivalent firewall rule.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.tlsCertFile == null) == (cfg.tlsKeyFile == null);
        message = ''
          services.holochain-bootstrap: set tlsCertFile and tlsKeyFile together,
          or neither. The server refuses one without the other.
        '';
      }
      {
        assertion = cfg.listenAddresses != [];
        message = "services.holochain-bootstrap.listenAddresses must name at least one address.";
      }
    ];

    systemd.services.holochain-bootstrap = {
      description = "Kitsune2 bootstrap and relay server";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      environment.RUST_LOG = cfg.logLevel;

      serviceConfig = {
        ExecStart = lib.escapeShellArgs ([(lib.getExe' cfg.package "kitsune2-bootstrap-srv")] ++ args);
        Restart = "on-failure";
        RestartSec = "5s";

        LoadCredential = lib.optionals tls [
          "tls-cert:${cfg.tlsCertFile}"
          "tls-key:${cfg.tlsKeyFile}"
        ];

        # No state: the store is tempfiles in this private /tmp.
        DynamicUser = true;
        PrivateTmp = true;
        UMask = "0077";

        AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
        CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];
        NoNewPrivileges = true;

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateDevices = true;
        PrivateUsers = false; # would drop CAP_NET_BIND_SERVICE in the host namespace
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RemoveIPC = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = ["@system-service" "~@privileged" "~@resources"];
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port];
      allowedUDPPorts = [cfg.quicPort];
    };
  };
}
