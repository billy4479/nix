{ pkgs, ... }:
let
  containerName = "jackett";
  configDir = "/mnt/SSD/apps/${containerName}/config";
  downloadsDir = "/mnt/SSD/apps/${containerName}/downloads";
  inherit (import ./utils.nix) givePermissions;
in
{
  virtualisation.oci-containers.containers."${containerName}" = {
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

    labels = {
      "io.containers.autoupdate" = "registry";
    };

    extraOptions = [ "--ip=10.0.1.8" ];
  };

}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ configDir ];
  userDirs = [ downloadsDir ];
})
