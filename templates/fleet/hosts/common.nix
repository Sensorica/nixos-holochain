# Shared by every fleet host. Per-machine files set the hostname, import their
# hardware-configuration.nix and add roles (node-01 adds Grafana).
{pkgs, ...}: {
  time.timeZone = "UTC";

  services.openssh.enable = true;

  users.users.operator = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    # Public keys are not secrets, and a flake only ever sees git-tracked
    # files, so operator keys live here rather than in an ignored file. Paste
    # your `ssh-ed25519 ...` line below before deploying; a fleet deployed with
    # this list empty has no way in over SSH.
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... operator@laptop"
    ];
  };

  # A desktop, because these nodes are meant to be sat in front of during a
  # workshop. Drop these three lines for headless servers.
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;
  environment.systemPackages = with pkgs; [git kdePackages.kate kdePackages.konsole firefox];

  services.holochain-edgenode = {
    enable = true;
    openFirewall = true;
    # node_exporter for the host series, and the conductor metrics timer for
    # the holochain_* series the fleet dashboard is built around. Every node
    # runs both; node-01 additionally scrapes and draws them.
    metricsExporter.enable = true;
    conductorMetrics.enable = true;

    # hApp bundles are fetched by hash and installed once, at first boot.
    #
    # happs.my-app = {
    #   src = ./my-app.happ;
    #   networkSeed = "my-network-2026";
    # };
  };

  # The Wind Tunnel runner is off on every node. It is not a dashboard data
  # source: it joins the machine to the Holochain Foundation's Nomad cluster
  # and runs the Foundation's scenarios, which is a donation of the machine,
  # not observability for this fleet. Turn it on per host if you mean to.
  services.holochain-windtunnel.enable = false;

  system.stateVersion = "25.05";
}
