{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/autologin.nix
    ../../modules/bluetooth.nix
    ../../modules/containers.nix
    ../../modules/graphics/intel.nix
    ../../modules/power-management
    ../../modules/desktops
  ];

  networking.hostName = "portatilo";
}
