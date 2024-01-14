{
  pkgs,
  user,
  desktop,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/autologin.nix
    ../../modules/bluetooth.nix
    ../../modules/containers.nix
    ../../modules/graphics/intel.nix
    (import ../../modules/desktops desktop)
  ];

  networking.hostName = "portatilo";
}
