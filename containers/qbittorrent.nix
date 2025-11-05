{ pkgs, ... }:
let
  containerName = "qbittorrent";
  downloadPath = "/mnt/HDD/torrent/${containerName}";
  configDir = "/mnt/SSD/apps/${containerName}";
  inherit (import ./utils.nix) givePermissions setCommonContainerConfig;

  torrentingPort = "6881";
  webUiPort = "8080";
in
{
  virtualisation.oci-containers.containers."${containerName}" = {
    image = "docker.io/qbittorrentofficial/qbittorrent-nox:latest";
    environment = {
      "QBT_LEGAL_NOTICE" = "confirm";
      "QBT_TORRENTING_PORT" = torrentingPort;
      "QBT_WEBUI_PORT" = webUiPort;
      "TZ" = "Europe/Rome";
    };
    volumes = [
      "${downloadPath}:/data/${containerName}:rw"
      "${configDir}:/config:rw"
    ];
    ports = [
      "${torrentingPort}:${torrentingPort}/tcp"
      "${torrentingPort}:${torrentingPort}/udp"
    ];
  }
  // (setCommonContainerConfig {
    ip = "10.0.1.5";
    tmpfs = [ "/tmp" ];
  });
}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ configDir ];
  userDirs = [ downloadPath ];
})
