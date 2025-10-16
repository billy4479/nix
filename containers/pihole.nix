{ pkgs, config, ... }:
let
  containerName = "pihole";
  baseSSDDir = "/mnt/SSD/apps/${containerName}";
  inherit (import ./utils.nix) givePermissions;
in
{
  sops.secrets.pihole-admin-password = { };

  virtualisation.oci-containers.containers."${containerName}" = {
    image = "docker.io/pihole/pihole:latest";
    # user = "5000:5000"; # This is intentionally commented since we need to bind port 80 and 53

    volumes = [
      "${baseSSDDir}:/etc/pihole:rw"
    ];

    labels = {
      "io.containers.autoupdate" = "registry";
    };

    environment = {
      "TZ" = "Europe/Rome";
      "FTLCONF_dns_upstreams" = "1.1.1.1;1.0.0.1";
      "PIHOLE_UID" = "5000";
      "PIHOLE_GID" = "5000";
    };
    environmentFiles = [
      config.sops.secrets.pihole-admin-password.path
    ];

    ports = [
      "53:53/tcp"
      "53:53/udp"
    ];

    extraOptions = [
      "--ip=10.0.1.11"
    ];
  };
}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ baseSSDDir ];
})
