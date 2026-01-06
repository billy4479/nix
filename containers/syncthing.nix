{ pkgs, config, ... }:
let
  inherit ((import ./utils.nix) { inherit pkgs config; }) makeContainer;

  configDir = "/mnt/SSD/apps/syncthing";
  dataDir1 = "/mnt/HDD/generic/Giacomo/Syncthing";
in
{
  # For QUIC
  boot.kernel.sysctl = {
    "net.core.rmem_max" = 7500000;
    "core.wmem_max" = 7500000;
  };
}
// makeContainer {

  name = "syncthing";
  image = "docker.io/syncthing/syncthing";
  ports = [
    "22000:22000/tcp"
    "22000:22000/udp"
    "21027:21027/udp"
  ];

  volumes = [
    {
      hostPath = "/mnt/SSD/apps/syncthing";
      containerPath = "/var/syncthing/config";
    }
    {
      hostPath = "/mnt/HDD/generic/Giacomo/Syncthing";
      containerPath = "/var/syncthing/Sync";
      userAccessible = true;
    }
  ];

  id = 2;
}
