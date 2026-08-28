{...}: {
  imports = [
    ../common.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "edgenode-03";
}
