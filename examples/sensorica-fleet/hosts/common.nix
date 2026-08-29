# Shared by every fleet host. Per-machine files set the hostname, import
# their hardware-configuration.nix and add roles (edgenode-01 adds Grafana).
{
  pkgs,
  fleetLine,
  fleetHapps,
  ...
}: {
  time.timeZone = "America/Montreal";

  services.openssh.enable = true;

  users.users.sensorica = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    # Operator public keys (ADR-012, revised): public keys are not secrets and
    # live here so every flake evaluation, nixos-rebuild and colmena apply sees
    # them. Paste your `ssh-ed25519 ...` line below before deploying; a fleet
    # deployed with this list empty has no way in over SSH.
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... operator@laptop"
    ];
  };

  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;

  environment.systemPackages = with pkgs; [git kdePackages.kate kdePackages.konsole firefox];

  services.holochain-edgenode = {
    enable = true;
    openFirewall = true;

    # The 0.6 line, chosen in flake.nix; see the comment on `fleetLine` there.
    # `hcPackage` must stay on the same line as `package`: the admin subcommand
    # is `hc sandbox call --running` below 0.7 and `hc client call --port` from
    # 0.7, and the module derives which one to use from `package.version`.
    package = fleetLine.holochain;
    hcPackage = fleetLine.hc;

    # node_exporter for the host series, and the conductor metrics timer for
    # the holochain_* series the fleet dashboard is built around. Every node
    # runs both; edgenode-01 additionally scrapes and draws them.
    metricsExporter.enable = true;
    conductorMetrics.enable = true;

    # Installed at boot from bundles fetched by hash, never committed
    # (ADR-006, ADR-012). One network seed for the whole fleet: it is what makes
    # the five nodes one DHT per app rather than five isolated ones, and it
    # keeps the workshop off the public networks these apps otherwise share.
    happs = {
      hrea = {
        src = fleetHapps.hrea;
        networkSeed = "sensorica-workshop-2026";
      };
      kando = {
        src = fleetHapps.kando;
        networkSeed = "sensorica-workshop-2026";
      };
      requests-and-offers = {
        src = fleetHapps.requests-and-offers;
        networkSeed = "sensorica-workshop-2026";
      };
    };

    # Three apps compile their wasm one after another on first boot, and a
    # Holoport is not a fast machine. The module polls for the outcome rather
    # than trusting the admin call's own deadline, so this is how long that
    # polling is allowed to last, not how long any single call may take.
    installerTimeout = 900;
  };

  # The Wind Tunnel runner stays off on every fleet node (ADR-008 as amended).
  # It is not a dashboard data source: it would join the machine to the
  # Holochain Foundation's Nomad cluster and run the Foundation's scenarios,
  # which is a donation of the machine, not observability for this fleet.
  services.holochain-windtunnel.enable = false;

  system.stateVersion = "25.05";
}
