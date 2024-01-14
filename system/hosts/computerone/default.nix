{desktop, ...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/desktops/qtile.nix
    ../../modules/graphics/nvidia.nix
    ../../modules/containers.nix

    (import ../../modules/desktops desktop)
  ];

  networking.hostName = "computerone";
}
