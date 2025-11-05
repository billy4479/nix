{ pkgs, ... }:
let
  containerName = "jellyfin";
  baseHDDDir = "/mnt/HDD/torrent";
  baseSSDDir = "/mnt/SSD/apps/${containerName}";
  inherit (import ./utils.nix) givePermissions setCommonContainerConfig;
in
{
  virtualisation.oci-containers.containers."${containerName}" = {
    image = "docker.io/jellyfin/jellyfin:latest";
    environment = {
      "TZ" = "Europe/Rome";
    };
    volumes = [
      "${baseHDDDir}:/media:rw"
      "${baseSSDDir}/config:/config:rw"
      "${baseSSDDir}/cache:/cache:rw"
    ];
  }
  // (setCommonContainerConfig {
    ip = "10.0.1.10";
    extraOptions = [
      "--device=/dev/dri:/dev/dri"
    ];
  });
}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ baseSSDDir ];
  userDirs = [ baseHDDDir ];
})
