{
  pkgs,
  lib,
  ...
}:
{
  # TODO: Not sure if this is needed
  networking.firewall = {
    allowedTCPPorts = [ 22000 ];
    allowedUDPPorts = [
      22000
      21027
    ];
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
      }
      {
        hostPath = "/mnt/SSD/apps/openchamber/workspaces/code";
        containerPath = "/var/syncthing/Sync/code";
      }
      {
        hostPath = "/mnt/SSD/apps/openchamber/workspaces/nix";
        containerPath = "/var/syncthing/Sync/nix";
      }
    ];

    id = 2;
    # OpenChamber and Syncthing must both own synchronized workspace files so
    # that permission synchronization does not revoke either service's access.
    uid = 5021;
    useNginx = true;
  };
}
