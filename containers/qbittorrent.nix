{ pkgs, ... }:
let
  containerName = "qbittorrent";
  torrentDestinationDir = "/mnt/HDD/torrent/${containerName}";
  baseSSDDir = "/mnt/SSD/apps/${containerName}";
  inherit (import ./utils.nix) givePermissions;

  torrentingPort = "6881";
  webUiPort = "8080";
in
{
  virtualisation.oci-containers.containers."${containerName}" = {
    image = "lscr.io/linuxserver/qbittorrent:latest";
    environment = {
      "PGID" = "5000";
      "PUID" = "5000";
      "TORRENTING_PORT" = torrentingPort;
      "TZ" = "Europe/Rome";
      "WEBUI_PORT" = webUiPort;
    };
    volumes = [
      "${torrentDestinationDir}:/data/${containerName}:rw"
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
}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ baseSSDDir ];
  userDirs = [ torrentDestinationDir ];
})
