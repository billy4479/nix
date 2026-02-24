{ pkgs, lib, ... }:
let
  name = "jellyfin";
  baseHDDDir = "/mnt/HDD/torrent";
  baseSSDDir = "/mnt/SSD/apps/${name}";
in
{
  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      config = {
        entrypoint = [ (lib.getExe pkgs.jellyfin) ];
        cmd = [
          "--datadir=/config"
          "--cachedir=/cache"
        ];
      };

      copyToRoot = with pkgs.dockerTools; [
        caCertificates
      ];
    };

    id = 10;

    volumes = [
      {
        hostPath = baseHDDDir;
        containerPath = "/media";
        readOnly = true;
      }
      {
        hostPath = "/mnt/HDD/generic";
        containerPath = "/generic-media";
        readOnly = true;
      }
      {
        hostPath = "${baseSSDDir}/config";
        containerPath = "/config";
      }
      {
        hostPath = "${baseSSDDir}/cache";
        containerPath = "/cache";
      }
    ];

    extraOptions = [
      "--device=/dev/dri:/dev/dri"
    ];
  };
}
