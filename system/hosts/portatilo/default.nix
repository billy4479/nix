{extraConfig, ...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/autologin.nix
    ../../modules/bluetooth.nix
    ../../modules/containers.nix
    ../../modules/graphics/intel.nix
    ../../modules/power-management

    (import ../../modules/desktops extraConfig.desktop)
  ];

  networking.hostName = "portatilo";
}
