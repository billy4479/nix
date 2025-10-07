{ pkgs, ... }:
let
  serviceName = "jackett";
  configDir = "/mnt/SSD/apps/${serviceName}/config";
  downloadsDir = "/mnt/SSD/apps/${serviceName}/downloads";
  port = "9117";
in
{
  virtualisation.oci-containers.containers."${serviceName}" = {
    image = "lscr.io/linuxserver/jackett:latest";
    environment = {
      "PGID" = "5000";
      "PUID" = "5000";
      "TZ" = "Europe/Rome";
    };
    volumes = [
      "${downloadsDir}:/downloads:rw"
      "${configDir}:/config:rw"
    ];
    ports = [
      # "${port}:${port}/tcp"
    ];

    labels = {
      "io.containers.autoupdate" = "registry";
    };

    extraOptions = [ "--ip=10.0.1.7" ];
  };

  systemd.services."podman-${serviceName}".postStart =
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

      f="${downloadsDir}"
      chown -R containers:containers $f
      ${setfacl} -R -m u:billy:rwx $f
      ${setfacl} -R -m d:u:billy:rwx $f
      echo "Set permissions for $f"
    '';
}
