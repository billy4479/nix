{ pkgs, ... }:
let
  containerName = "nginx";
  baseSSDDir = "/mnt/SSD/apps/${containerName}";
  certsDir = "/mnt/SSD/apps/certbot";
  inherit (import ../utils.nix) givePermissions setCommonContainerConfig;

  cloudflaredAddress = "10.0.1.131";

  config = pkgs.callPackage ./config.nix { inherit cloudflaredAddress; };
in
{
  virtualisation.oci-containers.containers."${containerName}" = {
    image = "docker.io/nginx:alpine";

    volumes = [
      "${config}/nginx.conf:/etc/nginx/nginx.conf:ro"
      "${config}/snippets:/etc/nginx/snippets:ro"

      "${baseSSDDir}/logs:/var/log/nginx:rw"
      "${certsDir}:/certs/:ro"
    ];

    ports = [
      "80:80/tcp"
      "443:443/tcp"
    ];
  }
  // (setCommonContainerConfig {
    ip = "10.0.1.6";
    tmpfs = [ "/tmp" ];
    runByUser = false; # We need to bind port 80 and 433
  });
}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ baseSSDDir ];
})
