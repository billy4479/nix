{ pkgs, config, ... }:
let
  name = "bind9";
  baseDir = "/mnt/SSD/apps/${name}";

  hosts = pkgs.callPackage ./hosts.nix { };
  bindConfig = pkgs.callPackage ./config.nix { bind9-hosts = hosts; };
in
{
  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      name = "bind9";
      tag = "nix-local";
      fromImage = pkgs.dockerTools.pullImage {
        imageName = "ubuntu/bind9";
        imageDigest = "sha256:360622f1481a577822b7a310cdca4e37c16c5d3af53a3e455a13e90cb234943f";
        hash = "sha256-D5w04BL0PzVm2vER+h78bG0mP7ugwxK6kVs9rQUjwhA=";
        finalImageName = "ubuntu/bind9";
        finalImageTag = "latest";
      };

      copyToRoot = [ ./contents ];
      config.Entrypoint = [ "/entrypoint.sh" ];
    };

    id = 11;
    runByUser = false; # Bind apparently _expects_ to be run as root
    dns = null;

    volumes = [
      {
        hostPath = "${baseDir}/cache";
        containerPath = "/var/cache/bind";
      }
      {
        hostPath = "${baseDir}/lib";
        containerPath = "/var/lib/bind";
      }
      {
        hostPath = "${baseDir}/log";
        containerPath = "/var/log";
      }
      {
        hostPath = "${bindConfig}";
        containerPath = "/etc/bind";
        readOnly = true;
      }
    ];

    environment = {
      "PUID" = "5000";
      "PGID" = "5000";
    };

    ports = [
      "53:53/tcp"
      "53:53/udp"
    ];
  };
}
