# modules/holochain-http-gateway.nix
#
# The Holochain HTTP gateway in front of the local conductor: it turns
# `GET /{dna-hash}/{app-id}/{zome}/{fn}?payload=<base64url JSON>` into a zome
# call over the conductor's app websocket, so a browser that cannot speak the
# websocket protocol can still read from a hApp.
#
# The binary is `hc-http-gw` from github.com/holochain/hc-http-gw, built per
# Holochain line in ../packages/holochain-http-gateway.nix and selected here
# from the conductor's own version, the same way the edgenode module derives
# its network section (ADR-009 as amended). It is not holonix's bundled
# `hc http-gw`.
#
# Everything the binary reads is an environment variable, documented in the
# project's `spec.md`; only `--address` and `--port` are also flags. The
# per-app variable `HC_GW_ALLOWED_FNS_<app-id>` carries the app id in its
# name, and systemd rejects an `Environment=` assignment whose name contains a
# dash, so those are passed through `env` in the launch script instead. The
# rest go in the unit's environment where `systemctl show` can print them.
#
# Nothing is exposed by default: with `allowedAppIds = []` the gateway starts
# and answers `/health`, and every zome-call path is refused.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.services.holochain-http-gateway;
  edgenode = config.services.holochain-edgenode;

  # Gateway 0.3.x speaks to a 0.6 conductor, 0.4.x to a 0.7 one; the client
  # protocol is not compatible across the two.
  gatewayLine =
    if lib.versionOlder edgenode.package.version "0.7"
    then "0.6"
    else "0.7";

  # Built against the nixpkgs holonix already pins, because the crate's
  # toolchain file asks for a rustc newer than nixos-25.05 carries.
  gatewayPkgs = inputs.holonix.inputs.nixpkgs.legacyPackages.${pkgs.system};

  defaultPackage = gatewayPkgs.callPackage ../packages/holochain-http-gateway.nix {
    line = gatewayLine;
  };

  wildcarded = lib.filterAttrs (_: fns: fns == ["*"]) cfg.allowedFns;

  # `*` is matched by the binary against the whole trimmed value, so it is
  # only ever legal on its own; a mixed list would make the gateway fail to
  # parse its configuration at startup.
  renderFns = fns:
    if fns == ["*"]
    then "*"
    else lib.concatStringsSep "," fns;

  perAppEnv =
    lib.mapAttrsToList
    (app: fns: lib.escapeShellArg "HC_GW_ALLOWED_FNS_${app}=${renderFns fns}")
    cfg.allowedFns;

  # `lib.warnIf` rather than a NixOS placeholder entry: this module carries no
  # placeholder any more, and the grep that proves it has to stay empty.
  launcher =
    lib.warnIf (wildcarded != {}) ''
      services.holochain-http-gateway.allowedFns exposes every function of ${lib.concatStringsSep ", " (lib.attrNames wildcarded)} through "*". The gateway does not tell reads from writes, so this publishes the app's write functions to anything that can reach ${cfg.address}:${toString cfg.port}.
    ''
    (pkgs.writeShellScript "hc-http-gw-launch" ''
      exec ${pkgs.coreutils}/bin/env ${lib.concatStringsSep " " perAppEnv} \
        ${lib.getExe cfg.package} \
          --address ${cfg.address} \
          --port ${toString cfg.port}
    '');
in {
  options.services.holochain-http-gateway = {
    enable = lib.mkEnableOption "the Holochain HTTP gateway in front of the local conductor";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalMD "the `hc-http-gw` release matching `services.holochain-edgenode.package.version`: 0.4.x for Holochain 0.7, 0.3.x for 0.6";
      description = ''
        The `hc-http-gw` package to run. The default is built from the tagged
        upstream source for the Holochain line the conductor runs, so it does
        not have to be set by hand when the conductor's line changes.
      '';
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address the gateway binds to, passed as `--address` (`HC_GW_ADDRESS`).
        The default keeps it on loopback; set it to `0.0.0.0` and turn on
        {option}`services.holochain-http-gateway.openFirewall` to serve a LAN.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8090;
      description = ''
        Port the gateway listens on, passed as `--port` (`HC_GW_PORT`).
      '';
    };

    adminPort = lib.mkOption {
      type = lib.types.port;
      default = edgenode.adminPort;
      defaultText = lib.literalExpression "config.services.holochain-edgenode.adminPort";
      description = ''
        Admin websocket port of the conductor the gateway drives. It becomes
        `HC_GW_ADMIN_WS_URL=ws://127.0.0.1:<adminPort>`, which the binary
        requires: without it the process exits immediately.
      '';
    };

    allowedAppIds = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["dino-adventure"];
      description = ''
        Installed app ids the gateway is allowed to reach, joined into
        `HC_GW_ALLOWED_APP_IDS`. Empty, the default, exposes nothing: the
        gateway runs and refuses every zome-call path. Each id listed here
        needs a matching entry in
        {option}`services.holochain-http-gateway.allowedFns`.
      '';
    };

    allowedFns = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {};
      example = lib.literalExpression ''
        {
          dino-adventure = ["dino_adventure/get_all_dinos_local"];
          my-app = ["*"];
        }
      '';
      description = ''
        Per app id, the zome functions the gateway may call, written
        `zome_name/fn_name`. Each entry becomes
        `HC_GW_ALLOWED_FNS_<app-id>`, a comma separated list.

        The single-element list `["*"]` allows every function in every zome of
        that app, which the binary accepts but which also exposes the app's
        writes, since the gateway does nothing else to tell a read from a
        write. Using it raises an evaluation warning. `*` cannot be mixed with
        named functions; the binary would fail to parse the value.
      '';
    };

    payloadLimitBytes = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 10240;
      description = ''
        Largest accepted `payload` query parameter, in bytes, as
        `HC_GW_PAYLOAD_LIMIT_BYTES`. Measured on the base64 text before it is
        decoded, so it is really a cap on the URL length the gateway will
        process. Upstream's own default is the same 10 KiB.
      '';
    };

    maxAppConnections = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 50;
      description = ''
        How many app websocket connections the gateway keeps open at once, one
        per allowed app, as `HC_GW_MAX_APP_CONNECTIONS`. Older connections are
        closed when the limit is reached.
      '';
    };

    zomeCallTimeoutMs = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 10000;
      description = ''
        Deadline for a single zome call, in milliseconds, as
        `HC_GW_ZOME_CALL_TIMEOUT_MS`. A call that outruns it answers 500.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open {option}`services.holochain-http-gateway.port` in the firewall.
        Leave it off unless the gateway is meant to be reachable from other
        machines; the conductor's admin interface is reachable through
        anything the gateway is allowed to call.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = edgenode.enable;
        message = ''
          services.holochain-http-gateway.enable requires
          services.holochain-edgenode.enable: the gateway drives a local
          conductor through its admin websocket.
        '';
      }
      {
        assertion = lib.all (app: cfg.allowedFns ? ${app}) cfg.allowedAppIds;
        message = let
          missing = lib.filter (app: !(cfg.allowedFns ? ${app})) cfg.allowedAppIds;
        in ''
          services.holochain-http-gateway.allowedFns has no entry for
          ${lib.concatStringsSep ", " missing}. The gateway refuses to start
          when an allowed app id has no HC_GW_ALLOWED_FNS_<app-id> variable.
        '';
      }
      {
        assertion = lib.all (fns: !(lib.elem "*" fns) || fns == ["*"]) (lib.attrValues cfg.allowedFns);
        message = ''
          services.holochain-http-gateway.allowedFns mixes "*" with named
          functions. The gateway matches "*" against the whole value, so a
          mixed list fails to parse and the service does not start.
        '';
      }
    ];

    systemd.services.holochain-http-gateway = {
      description = "Holochain HTTP gateway";
      after = ["network.target" "holochain-conductor.service"];
      wants = ["network.target"];
      requires = ["holochain-conductor.service"];
      wantedBy = ["multi-user.target"];

      environment = {
        HC_GW_ADMIN_WS_URL = "ws://127.0.0.1:${toString cfg.adminPort}";
        HC_GW_ADDRESS = cfg.address;
        HC_GW_PORT = toString cfg.port;
        HC_GW_ALLOWED_APP_IDS = lib.concatStringsSep "," cfg.allowedAppIds;
        HC_GW_PAYLOAD_LIMIT_BYTES = toString cfg.payloadLimitBytes;
        HC_GW_MAX_APP_CONNECTIONS = toString cfg.maxAppConnections;
        HC_GW_ZOME_CALL_TIMEOUT_MS = toString cfg.zomeCallTimeoutMs;
      };

      serviceConfig = {
        ExecStart = launcher;
        Type = "simple";

        # The conductor can still be replaying its databases when the
        # gateway first resolves the admin websocket, and the gateway exits
        # rather than waiting.
        Restart = "always";
        RestartSec = 1;

        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = ["@system-service" "~@privileged" "~@resources"];
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
  };
}
