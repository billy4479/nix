{ pkgs, ... }:
let
  containerName = "cloudflared";
  baseSSDDir = "/mnt/SSD/apps/${containerName}";
  inherit (import ./utils.nix) givePermissions;
in
{
  virtualisation.oci-containers.containers."${containerName}" = {
    image = "docker.io/erisamoe/cloudflared:latest";
    user = "5000:5000";

    volumes = [
      "${baseSSDDir}:/etc/cloudflared:rw"
    ];

    cmd = [
      "tunnel"
      "run"
      "nas"
    ];

    labels = {
      "io.containers.autoupdate" = "registry";
    };

    extraOptions = [ "--ip=10.0.1.131" ];
  };
}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ baseSSDDir ];
})
