{ pkgs, ... }:
let
  torrentDestinationDir = "/mnt/HDD/torrent";
  baseSSDDir = "/mnt/SSD/apps/qbittorrent";

  torrentingPort = "6881";
  webUiPort = "8080";
in
{
  virtualisation.oci-containers.containers."qbittorrent" = {
    image = "lscr.io/linuxserver/qbittorrent:latest";
    environment = {
      "PGID" = "5000";
      "PUID" = "5000";
      "TORRENTING_PORT" = torrentingPort;
      "TZ" = "Europe/Rome";
      "WEBUI_PORT" = webUiPort;
    };
    volumes = [
      "${torrentDestinationDir}:/downloads:rw"
      "${baseSSDDir}:/config:rw"
    ];
    ports = [
      # "${webUiPort}:${webUiPort}/tcp"
      "${torrentingPort}:${torrentingPort}/tcp"
      "${torrentingPort}:${torrentingPort}/udp"
    ];

    labels = {
      "io.containers.autoupdate" = "registry";
    };

    extraOptions = [ "--ip=10.0.1.5" ];
  };

  systemd.services.podman-qbittorrent.postStart =
    let
      setfacl = "${pkgs.acl}/bin/setfacl";
    in
    # sh
    ''
      sleep 5

      f="${baseSSDDir}"
      chown -R containers:containers $f
      ${setfacl} -R -m g:admin:rwx $f
      ${setfacl} -R -m d:g:admin:rwx $f
      echo "Set permissions for $f"

      f="${torrentDestinationDir}"
      chown -R containers:containers $f
      ${setfacl} -R -m u:billy:rwx $f
      ${setfacl} -R -m d:u:billy:rwx $f
      echo "Set permissions for $f"
    '';
}
