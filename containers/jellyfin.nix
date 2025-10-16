{ pkgs, ... }:
let
  containerName = "jellyfin";
  baseHDDDir = "/mnt/HDD/torrent";
  configDir = "/mnt/SSD/apps/${containerName}";
  inherit (import ./utils.nix) givePermissions;
in
{
  virtualisation.oci-containers.containers."${containerName}" = {
    image = "lscr.io/linuxserver/jellyfin:latest";
    environment = {
      "PGID" = "5000";
      "PUID" = "5000";
      "TZ" = "Europe/Rome";
    };
    volumes = [
      "${baseHDDDir}:/data:rw"
      "${configDir}:/config:rw"
    ];

    # TODO: remove this
    ports = [
      "8096:8096"
    ];

    labels = {
      "io.containers.autoupdate" = "registry";
    };

    extraOptions = [
      "--ip=10.0.1.10"
      "--device=/dev/dri:/dev/dri"
    ];
  };
}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ configDir ];
  userDirs = [ baseHDDDir ];
})
