# Shared by every fleet host. Per-machine files set the hostname, import
# their hardware-configuration.nix and add roles (edgenode-01 adds Grafana).
{pkgs, ...}: {
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

  # hApps are installed at boot from bundles fetched by hash; slice 2 adds them (ADR-006, ADR-012).
  services.holochain-edgenode = {
    enable = true;
    openFirewall = true;
    metricsExporter.enable = true;
  };

  system.stateVersion = "25.05";
}
