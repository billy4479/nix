{ extraConfig, flakeInputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./xrandr.nix
    ../../modules/containers.nix
    ../../modules/virtualization.nix
    ../../modules/graphics/nvidia.nix

    ../../modules/cifs-client.nix
    ../../modules/wireguard.nix
    ../../modules/extra-network.nix

    ../../modules/desktops
  ];

  networking.hostName = "computerone";

  users.users.${extraConfig.user.username}.openssh.authorizedKeys.keys = [
    (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_portatilo.pub")
  ];

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
}
