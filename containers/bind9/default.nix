{ pkgs, ... }:
let
  containerName = "bind9";
  baseDir = "/mnt/SSD/apps/${containerName}";
  inherit (import ../utils.nix) givePermissions setCommonContainerConfig;

  hosts = pkgs.callPackage ./hosts.nix { };
  config = pkgs.callPackage ./config.nix { bind9-hosts = hosts; };
in
{
  virtualisation.oci-containers.containers."${containerName}" = {
    imageFile =
      with pkgs.dockerTools;
      buildLayeredImage {
        name = "bind9";
        tag = "latest";
        fromImage = pullImage {
          imageName = "ubuntu/bind9";
          imageDigest = "sha256:360622f1481a577822b7a310cdca4e37c16c5d3af53a3e455a13e90cb234943f";
          hash = "sha256-D5w04BL0PzVm2vER+h78bG0mP7ugwxK6kVs9rQUjwhA=";
          finalImageName = "ubuntu/bind9";
          finalImageTag = "latest";
        };

        contents = [ ./contents ];
        config.Entrypoint = [ "/entrypoint.sh" ];
      };
    image = "localhost/bind9:latest";
    volumes = [
      "${baseDir}/cache:/var/cache/bind:rw"
      "${baseDir}/lib:/var/lib/bind:rw"
      "${baseDir}/log:/var/log:rw"
      "${config}:/etc/bind:ro"
    ];

    environment = {
      "TZ" = "Europe/Rome";
      "PUID" = "5000";
      "PGID" = "5000";
    };

    ports = [
      "53:53/tcp"
      "53:53/udp"
    ];
  }
  // (setCommonContainerConfig {
    ip = "10.0.1.11";
    runByUser = false;
    dns = null;
  });
}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ baseDir ];
})
