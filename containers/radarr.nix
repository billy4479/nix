{ pkgs, ... }:
let
  containerName = "radarr";
  baseHDDDir = "/mnt/HDD/torrent";
  configDir = "/mnt/SSD/apps/${containerName}";
  inherit (import ./utils.nix) givePermissions;
in
{
  virtualisation.oci-containers.containers."${containerName}" = {
    image = "lscr.io/linuxserver/radarr:latest";
    environment = {
      "PGID" = "5000";
      "PUID" = "5000";
      "TZ" = "Europe/Rome";
    };
    volumes = [
      "${baseHDDDir}:/data:rw"
      "${configDir}:/config:rw"
    ];

    labels = {
      "io.containers.autoupdate" = "registry";
    };

    extraOptions = [ "--ip=10.0.1.7" ];
  };
}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ configDir ];
  userDirs = [ baseHDDDir ];
})
