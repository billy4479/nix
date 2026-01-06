{ pkgs, config, ... }:
let
  inherit ((import ./utils.nix) { inherit pkgs config; }) makeContainer;

  name = "qbittorrent";
  downloadPath = "/mnt/HDD/torrent/${name}";
  configDir = "/mnt/SSD/apps/${name}";

  torrentingPort = "6881";
  webUiPort = "8080";
in
makeContainer {
  inherit name;
  image = "docker.io/qbittorrentofficial/qbittorrent-nox";
  id = 5;

  environment = {
    "QBT_LEGAL_NOTICE" = "confirm";
    "QBT_TORRENTING_PORT" = torrentingPort;
    "QBT_WEBUI_PORT" = webUiPort;
  };

  volumes = [
    {
      hostPath = downloadPath;
      containerPath = "/data/${name}";
      userAccessible = true;
    }
    {
      hostPath = configDir;
      containerPath = "/config";
    }
  ];

  ports = [
    "${torrentingPort}:${torrentingPort}/tcp"
    "${torrentingPort}:${torrentingPort}/udp"
  ];
}
