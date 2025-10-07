{ pkgs, ... }:
let
  dataDir = "/mnt/HDD/torrent";
  configDir = "/mnt/SSD/apps/radarr";
  port = "7878";
in
{
  virtualisation.oci-containers.containers."radarr" = {
    image = "ghcr.io/hotio/radarr:latest";
    environment = {
      "PGID" = "5000";
      "PUID" = "5000";
      "UMASK" = "002";
      "TZ" = "Europe/Rome";
    };
    volumes = [
      "${dataDir}:/data:rw"
      "${configDir}:/config:rw"
    ];
    ports = [
      # "${port}:${port}/tcp"
    ];

    labels = {
      "io.containers.autoupdate" = "registry";
    };

    extraOptions = [ "--ip=10.0.1.6" ];
  };

  systemd.services.podman-radarr.postStart =
    let
      setfacl = "${pkgs.acl}/bin/setfacl";
    in
    # sh
    ''
      sleep 5

      f="${configDir}"
      chown -R containers:containers $f
      ${setfacl} -R -m g:admin:rwx $f
      ${setfacl} -R -m d:g:admin:rwx $f
      echo "Set permissions for $f"

      f="${dataDir}"
      chown -R containers:containers $f
      ${setfacl} -R -m u:billy:rwx $f
      ${setfacl} -R -m d:u:billy:rwx $f
      echo "Set permissions for $f"
    '';
}
