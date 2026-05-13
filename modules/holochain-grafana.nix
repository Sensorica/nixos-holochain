# modules/holochain-grafana.nix
#
# Prometheus + Grafana observability module for a Holochain fleet.
# Enable on the designated monitor node; all peer nodes should set
# services.holochain-edgenode.metricsExporter.enable = true.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.holochain-grafana;
in
{
  options.services.holochain-grafana = {
    enable = lib.mkEnableOption "Prometheus + Grafana observability for Holochain fleet";

    grafanaPort = lib.mkOption {
      type        = lib.types.port;
      default     = 3000;
      description = "Port Grafana listens on.";
    };

    prometheusPort = lib.mkOption {
      type        = lib.types.port;
      default     = 9090;
      description = "Port Prometheus listens on.";
    };

    scrapeTargets = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [];
      description = "Prometheus node_exporter targets across the fleet (host:port).";
      example     = lib.literalExpression ''
        [ "edgenode-01:9100" "edgenode-02:9100" "edgenode-03:9100"
          "edgenode-04:9100" "edgenode-05:9100" ]
      '';
    };

    windtunnelTargets = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [];
      description = "Wind Tunnel Prometheus metrics targets (host:port). Leave empty until Wind Tunnel binary is available.";
      example     = lib.literalExpression ''
        [ "edgenode-01:9101" "edgenode-02:9101" ]
      '';
    };

    openFirewall = lib.mkOption {
      type        = lib.types.bool;
      default     = false;
      description = "Open firewall ports for Grafana, Prometheus, and node_exporter.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_port    = cfg.grafanaPort;
          http_addr    = "0.0.0.0";
          domain       = "localhost";
          root_url     = "http://localhost:${toString cfg.grafanaPort}/";
        };
        security = {
          admin_user     = "admin";
          admin_password = "workshop2026";
        };
        analytics.reporting_enabled = false;
      };
    };

    services.prometheus = {
      enable = true;
      port   = cfg.prometheusPort;

      scrapeConfigs = [
        {
          job_name       = "holochain-nodes";
          static_configs = [{ targets = cfg.scrapeTargets; }];
        }
      ] ++ lib.optional (cfg.windtunnelTargets != []) {
        job_name       = "windtunnel";
        static_configs = [{ targets = cfg.windtunnelTargets; }];
      };
    };

    # Monitor node also exports its own system metrics
    services.prometheus.exporters.node = {
      enable             = true;
      port               = 9100;
      enabledCollectors  = [ "systemd" ];
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.grafanaPort cfg.prometheusPort 9100 ];
    };
  };
}
