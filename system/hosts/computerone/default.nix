{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./xrandr.nix
    ../../modules/containers.nix
    ../../modules/virtualization.nix
    ../../modules/desktops/qtile.nix
    ../../modules/graphics/nvidia.nix

    ../../modules/desktops
  ];

  networking.hostName = "computerone";

  fileSystems = {
    "/".options = [
      "defaults"
      "discard"
    ];
    "/boot".options = [
      "defaults"
      "discard"
    ];

    "/mnt/NVMe".options = [
      "defaults"
      "discard"
      "noauto"
      "users"
    ];

    "/mnt/HDD".options = [
      "defaults"
      "noauto"
      "users"
    ];
  };
}
