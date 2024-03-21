{extraConfig, ...}: {
  imports = [
    ./hardware-configuration.nix
    ./xorg.nix
    ../../modules/containers.nix
    ../../modules/desktops/qtile.nix
    ../../modules/graphics/nvidia.nix

    (import ../../modules/desktops extraConfig.desktop)
  ];

  networking.hostName = "computerone";
}
