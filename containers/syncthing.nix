{ pkgs, ... }:
{

  virtualisation.oci-containers.containers = {
    syncthing = {
      autoStart = true;

      image = "lscr.io/linuxserver/syncthing:latest";
      ports = [
        "8384:8384"
        "22000:22000/tcp"
        "22000:22000/udp"
        "21027:21027/udp"
      ];

      environment = {
        UID = "1000";
        GID = "1000";
        TZ = "Europe/Rome";
      };

      volumes = [
        "/mnt/SSD/apps/syncthing/config:/config"
        "/mnt/HDD/generic/syncthing-data:/data"
      ];

      extraOptions = [ "--ip=10.0.1.2" ];
    };
  };

}
