{ pkgs, lib, ... }:
let
  name = "qbittorrent";

  torrentingPort = "6881";
  webUiPort = "8080";
in
{
  nerdctl-containers.${name} = {
    imageToPull = "docker.io/qbittorrentofficial/qbittorrent-nox";
    id = 5;

    environment = {
      "QBT_LEGAL_NOTICE" = "confirm";
      "QBT_TORRENTING_PORT" = torrentingPort;
      "QBT_WEBUI_PORT" = webUiPort;
    };

    volumes = [
      {
        hostPath = "/mnt/HDD/torrent/${name}";
        containerPath = "/data/${name}";
        userAccessible = true;
        customPermissionScript = ''
          currentPerm=$(stat -c %u:%g "/mnt/HDD/torrent/${name}")
          if [ "$currentPerm" != "5005:5000" ]; then
            echo "Fixing permissions for /mnt/HDD/torrent/${name} (non-recursive)"
            chown 5005:5000 "/mnt/HDD/torrent/${name}"
            chmod g+rwX "/mnt/HDD/torrent/${name}"
            ${lib.getExe' pkgs.acl "setfacl"} -m d:g:family:rwX,g:family:rwX "/mnt/HDD/torrent/${name}"
          fi
        '';
      }
      {
        hostPath = "/mnt/SSD/apps/${name}";
        containerPath = "/config";
      }
    ];

    ports = [
      "${torrentingPort}:${torrentingPort}/tcp"
      "${torrentingPort}:${torrentingPort}/udp"
    ];
  };
}
