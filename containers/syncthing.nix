{
  pkgs,
  lib,
  ...
}:
{
  # For QUIC
  boot.kernel.sysctl = {
    "net.core.rmem_max" = 7500000;
    "core.wmem_max" = 7500000;
  };

  nerdctl-containers.syncthing = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      name = "syncthing";
      tag = "nix-local";

      copyToRoot = [ pkgs.dockerTools.caCertificates ];

      config = {
        entrypoint = [ "${lib.getExe pkgs.syncthing}" ];
        env = [
          "HOME=/var/syncthing"
          "STHOMEDIR=/var/syncthing/config"
          "STGUIADDRESS=0.0.0.0:8384"
        ];
      };
    };
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
        hostPath = "/mnt/HDD/apps/syncthing";
        containerPath = "/var/syncthing/Sync";
        userAccessible = true;
      }
    ];

    id = 2;
  };
}
