{ pkgs, ... }:
let
  containerName = "nginx";
  baseSSDDir = "/mnt/SSD/apps/${containerName}";
  certsDir = "/mnt/SSD/apps/certbot";
  inherit (import ./utils.nix) givePermissions;
in
{
  virtualisation.oci-containers.containers."${containerName}" = {
    image = "docker.io/nginx:alpine";
    # user = "5000:5000"; # This is intentionally commented since we need to bind port 80 and 433

    volumes = [
      "${baseSSDDir}/nginx.conf:/etc/nginx/nginx.conf:ro"
      "${baseSSDDir}/logs:/var/log/nginx:rw"
      "${certsDir}:/certs/:ro"
    ];

    labels = {
      "io.containers.autoupdate" = "registry";
    };

    extraOptions = [
      "--ip=10.0.1.6"
      "--tmpfs"
      "/tmp"
    ];
  };
}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ baseSSDDir ];
})
