{...}: {
  imports = [
    ../common.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "sensorica-holoport-04";

  # Switches for this Holoport. Change one, save, then run `rebuild`; each
  # generation stays in the boot menu, so a switch that goes wrong is undone
  # with `sudo nixos-rebuild switch --rollback`.
  sensorica.desktop = "plasma"; # "plasma" (KDE), "gnome" or "none" (text console only)
  sensorica.eventMode.enable = false; # true: no login, the room dashboard full screen at boot
  services.holochain-edgenode.enable = true; # false: no Holochain conductor, no hApps
  sensorica.remoteAccess.enable = false; # true once Headscale runs and the key is in /var/lib/secrets/headscale-authkey
}
