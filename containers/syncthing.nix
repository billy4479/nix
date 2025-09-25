{ pkgs, ... }:
{
  virtualisation.oci-containers.containers = {
    syncthing = {
      autoStart = true;
      user = "5000:5000";

      image = "docker.io/syncthing/syncthing:latest";
      ports = [
        "8384:8384"
        "22000:22000/tcp"
        "22000:22000/udp"
        "21027:21027/udp"
      ];

      environment = {
        # TZ = "Europe/Rome";
      };

      volumes = [
        "/mnt/SSD/apps/syncthing:/var/syncthing/config"
        "/mnt/HDD/generic/Giacomo/Syncthing:/var/syncthing/Sync"
      ];

      labels = {
        "io.containers.autoupdate" = "registry";
      };

      extraOptions = [ "--ip=10.0.1.2" ];
    };
  };

  systemd.services.podman-syncthing.postStart =
    let
      setfacl = "${pkgs.acl}/bin/setfacl";
    in
    # sh
    ''
      sleep 5

      f="/mnt/SSD/apps/syncthing"
      chown -R containers:containers $f
      ${setfacl} -R -m g:admin:rwx $f
      ${setfacl} -R -m d:g:admin:rwx $f
      echo "Set permissions for $f"

      f="/mnt/HDD/generic/Giacomo/Syncthing"
      chown -R containers:containers $f
      ${setfacl} -R -m u:billy:rwx $f
      ${setfacl} -R -m d:u:billy:rwx $f
      echo "Set permissions for $f"
    '';

  # For QUIC
  boot.kernel.sysctl = {
    "net.core.rmem_max" = 7500000;
    "core.wmem_max" = 7500000;
  };

}
