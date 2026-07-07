{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./xrandr.nix
    ../../modules/containers.nix
    ../../modules/virtualization.nix
    ../../modules/graphics/nvidia.nix

    ../../modules/cifs-client.nix
    ../../modules/smartd.nix
    ../../modules/tailscale.nix
    ../../modules/extra-network.nix

    ../../modules/desktops
  ];

  networking.hostName = "computerone";

  # FIXME: Re-enable ZFS when zfs-kernel is no longer marked broken in nixpkgs.
  # boot.supportedFilesystems = [ "zfs" ];
  # boot.zfs.forceImportRoot = false;
  # networking.hostId = "2b1efe27";

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
      "uid=1000"
      "gid=1000"
      "x-systemd.automount"
      "x-systemd.idle-timeout=5m"
      "x-systemd.device-timeout=1s"
      "x-systemd.mount-timeout=1s"
    ];

    "/mnt/HDD".options = [
      "defaults"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=5m"
      "x-systemd.device-timeout=1s"
      "x-systemd.mount-timeout=1s"
    ];
  };

  swapDevices = [
    {
      device = "/swapfile";
      options = [
        "defaults"
        "nofail"
      ];
      size = 64 * 1024;
    }
  ];
}
