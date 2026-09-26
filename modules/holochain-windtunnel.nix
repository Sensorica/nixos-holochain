# modules/holochain-windtunnel.nix
#
# Runs the Holochain Foundation's Wind Tunnel runner image as an OCI container
# (ADR-008, as amended by research record #15).
#
# This module is NOT a source of dashboard data, and enabling it does not make
# anything appear in Grafana. The image's entrypoint is
#
#   chronyd -q 'server pool.ntp.org iburst'
#   exec nomad agent -config=<baked nomad.json> -config=/etc/nomad.d
#
# and the baked config sets `client.servers = ["nomad-server-01.holochain.org"]`,
# so the machine joins the Foundation's Nomad cluster as a client and the
# Foundation schedules Wind Tunnel scenarios (each with its own conductor) onto
# it. Both facts were read out of the pulled image, not out of documentation.
#
# The fleet's own `holochain_*` series come from
# `services.holochain-edgenode.conductorMetrics`, which is a separate module and
# needs none of this.
{
  config,
  lib,
  ...
}: let
  cfg = config.services.holochain-windtunnel;
in {
  options.services.holochain-windtunnel = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Donate this machine to the Holochain Foundation's Wind Tunnel test
        network.

        The container runs its own Holochain conductor and reports to the
        Foundation's Nomad cluster at `nomad-server-01.holochain.org`; the
        runner's own README calls these machines "designed to be for internal
        use only" and warns that the image "requires extensive permissions on
        the host machine that are effectively root access" and "should only be
        run on a dedicated machine".

        Enabling this donates the machine. It does not feed the fleet
        dashboard: the `holochain_*` series come from
        `services.holochain-edgenode.conductorMetrics`, and nothing in this
        module exposes a Prometheus endpoint. Off by default, deliberately.
      '';
    };

    backend = lib.mkOption {
      type = lib.types.enum ["podman" "docker"];
      default = "podman";
      description = ''
        OCI backend used to run the container. Podman is the default: it needs
        no daemon and the NixOS module wires the unit to it directly. The
        runner's README documents Docker, and the image is indifferent to
        which one starts it.
      '';
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/holochain/wind-tunnel-runner@sha256:650c91806275681bc1961e0e55e85fa7fbf31bebe0c8665fc0a6af71ac330fa2";
      description = ''
        Runner image, pinned by digest.

        `ghcr.io/holochain/wind-tunnel-runner` publishes only the moving tags
        `latest`, `latest-amd64` and `latest-arm64`, so a tag pin would silently
        change what a fleet runs. The default is the multi-architecture index
        digest that `latest` resolved to on 2026-08-28, which keeps `amd64` and
        `arm64` hosts on the same pin. Re-pin with

          skopeo inspect docker://ghcr.io/holochain/wind-tunnel-runner:latest
      '';
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "nomad-client-${config.networking.hostName}";
      defaultText = lib.literalExpression ''"nomad-client-''${config.networking.hostName}"'';
      description = ''
        Hostname the container reports to the Nomad cluster, passed as
        `--hostname`. The runner's README asks for a unique, recognisable
        `nomad-client-<user>` style name, since it is how the machine is
        identified in the Nomad and Tailscale dashboards.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Start the container at boot. Set to false to keep the unit generated
        but idle, which is what the VM test does: the test sandbox has no
        network, so the image cannot be pulled there.
      '';
    };

    extraOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["--net=host" "--privileged" "--cgroupns=host"];
      description = ''
        Flags passed to `podman run` / `docker run`. The default is the set the
        runner's README requires: host networking, privileged, and the host
        cgroup namespace, so the Nomad agent inside can schedule and supervise
        its own workloads. Removing any of them stops the runner from working;
        they are an option only so that a host with a conflicting device or
        network setup can adjust them knowingly.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers = {
      backend = lib.mkDefault cfg.backend;
      containers.wind-tunnel-runner = {
        inherit (cfg) image extraOptions autoStart hostname;
        # The image publishes only moving tags, so "pull if absent" is the only
        # sane policy for a digest pin: the digest cannot drift, and re-pulling
        # on every restart would put a fleet's boot time on GHCR's availability.
        pull = "missing";
      };
    };
  };
}
