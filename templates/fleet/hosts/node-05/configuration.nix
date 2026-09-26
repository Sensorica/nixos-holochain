{...}: {
  imports = [
    ../common.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "node-05";
}
