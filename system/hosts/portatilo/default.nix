{extraConfig, ...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/autologin.nix
    ../../modules/bluetooth.nix
    ../../modules/containers.nix
    ../../modules/graphics/intel.nix

    (import ../../modules/desktops extraConfig.desktop)
  ];

  networking.hostName = "portatilo";
}
