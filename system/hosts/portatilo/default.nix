{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/autologin.nix
    ../../modules/bluetooth.nix
    ../../modules/containers.nix
    ../../modules/iphone.nix
    ../../modules/graphics/intel.nix
    ../../modules/power-management
    ../../modules/desktops

    ../../modules/cifs-client.nix
    ../../modules/tailscale.nix
    ../../modules/extra-network.nix
  ];

  networking.hostName = "portatilo";
}
