{ pkgs, ... }:
let
  containerName = "flaresolverr";
  baseSSDDir = "/mnt/SSD/apps/${containerName}";
  inherit (import ./utils.nix) givePermissions;
in
{
  virtualisation.oci-containers.containers."${containerName}" = {
    image = "ghcr.io/flaresolverr/flaresolverr:latest";
    environment = {
      "LOG_LEVEL" = "info";
      "TZ" = "Europe/Rome";
    };

    volumes = [
      "${baseSSDDir}/local:/app/.local:rw"
    ];

    labels = {
      "io.containers.autoupdate" = "registry";
    };

    extraOptions = [
      "--ip=10.0.1.133"
      "--tmpfs"
      "/app/.cache"
    ];
  };
}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ baseSSDDir ];
})
