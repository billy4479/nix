{ ... }:
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
