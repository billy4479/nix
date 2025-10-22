{ pkgs, ... }:
let
  containerName = "jackett";
  configDir = "/mnt/SSD/apps/${containerName}/config";
  downloadsDir = "/mnt/SSD/apps/${containerName}/downloads";
  inherit (import ./utils.nix) givePermissions setCommonContainerConfig;
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
  }
  // (setCommonContainerConfig {
    ip = "10.0.1.8";
    runByUser = false;
  });
}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ configDir ];
  userDirs = [ downloadsDir ];
})
