{ extraConfig, ... }: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/containers.nix
    ../../modules/desktops/qtile.nix
    ../../modules/graphics/nvidia.nix

    (import ../../modules/desktops extraConfig.desktop)
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
