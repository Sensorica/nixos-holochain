# observability/service-readings.nix
#
# The `holochain_service_*` series a node publishes about its own services
# (AD5): one `holochain_service_info` line per unit, and the health checks'
# `holochain_service_healthy` and the time they last ran. The module that
# owns the options, modules/holochain/holochain-services.nix, calls this with
# its configuration and installs what it returns.
{
  lib,
  pkgs,
  units,
  healthChecks,
  textfileDirectory,
}: let
  # A Prometheus label value: backslash, double quote and newline escaped.
  labelValue = value: builtins.replaceStrings ["\\" "\"" "\n"] ["\\\\" "\\\"" "\\n"] value;

  infoFile = pkgs.writeText "holochain-services.prom" (''
      # HELP holochain_service_info A service this node runs that the Holochain dashboards watch, by the name a person reads for it (service), the version of what it runs (version, when known), and, for a conductor, the conductor label its readings carry and the Holochain version it runs (holochain_version). Always 1.
      # TYPE holochain_service_info gauge
    ''
    + lib.concatStrings (lib.mapAttrsToList (unit: service: ''
        holochain_service_info{${lib.optionalString (service.conductor != null) ''conductor="${labelValue service.conductor}",''}${lib.optionalString (service.holochainVersion != "") ''holochain_version="${labelValue service.holochainVersion}",''}name="${labelValue unit}",service="${labelValue service.name}"${lib.optionalString (service.version != "") '',version="${labelValue service.version}"''}} 1
      '')
      units));

  # Every check runs before anything is written, so the file is written in
  # one piece, each family's lines together, as node_exporter requires.
  healthScript = pkgs.writeShellScript "holochain-service-health" ''
    set -u
    dir=${lib.escapeShellArg textfileDirectory}
    now=$(${pkgs.coreutils}/bin/date +%s)
    ${lib.concatStrings (lib.imap0 (i: unit: let
      check = healthChecks.${unit};
    in ''
      if ${pkgs.curl}/bin/curl -sf -o /dev/null --max-time ${toString check.timeoutSeconds} ${lib.optionalString check.insecure "-k "}${lib.escapeShellArg check.url}; then
        healthy_${toString i}=1
      else
        healthy_${toString i}=0
      fi
    '') (lib.attrNames healthChecks))}
    {
      echo '# HELP holochain_service_healthy 1 when the service answered its health check, 0 when it did not.'
      echo '# TYPE holochain_service_healthy gauge'
      ${lib.concatStrings (lib.imap0 (i: unit: ''
      echo ${lib.escapeShellArg ''holochain_service_healthy{name="${labelValue unit}"}''} "$healthy_${toString i}"
    '') (lib.attrNames healthChecks))}
      echo '# HELP holochain_service_health_timestamp_seconds When the service health checks last ran, as a Unix time.'
      echo '# TYPE holochain_service_health_timestamp_seconds gauge'
      ${lib.concatStrings (map (unit: ''
      echo ${lib.escapeShellArg ''holochain_service_health_timestamp_seconds{name="${labelValue unit}"}''} "$now"
    '') (lib.attrNames healthChecks))}
    } > "$dir/.holochain-service-health.prom.tmp"
    mv "$dir/.holochain-service-health.prom.tmp" "$dir/holochain-service-health.prom"
  '';
in {
  inherit infoFile healthScript;
}
