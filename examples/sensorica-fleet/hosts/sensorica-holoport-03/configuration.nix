{...}: {
  imports = [
    ../common.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "sensorica-holoport-03";

  # Switches for this Holoport. Change one, save, then run `rebuild`; each
  # generation stays in the boot menu, so a switch that goes wrong is undone
  # with `sudo nixos-rebuild switch --rollback`.
  sensorica.desktop = "plasma"; # "plasma" (KDE), "gnome" or "none" (text console only)
  sensorica.eventMode.enable = false; # true: no login, the room dashboard full screen at boot
  services.holochain-edgenode.enable = true; # false: no Holochain conductor, no hApps
  sensorica.remoteAccess.enable = false; # true once Headscale runs and the key is in /var/lib/secrets/headscale-authkey

  # A fixed LAN address, like sensorica-holoport-01's .5: the lab's Virgin
  # Plus hub shows no reservation form, and .6 to .9 sit below its DHCP pool
  # (.10 to .254), so no lease can collide. Holoport N answers at .(4+N).
  # Ethernet only, as on every NixOS server we run.
  networking.useDHCP = false;
  networking.interfaces.enp1s0.ipv4.addresses = [
    {
      address = "192.168.2.7";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = {
    address = "192.168.2.1";
    interface = "enp1s0";
  };
  networking.nameservers = ["192.168.2.1" "1.1.1.1" "9.9.9.9"];
}
