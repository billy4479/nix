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

      copyToRoot = with pkgs; [
        dockerTools.caCertificates
        intel-media-driver
        intel-vaapi-driver
        vpl-gpu-rt
      ];
    };

    id = 10;
    useNginx = true;

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

    environment = {
      LIBVA_DRIVER_NAME = "iHD";
      LIBVA_DRIVER_PATH = "${pkgs.intel-media-driver}/lib/dri:${pkgs.intel-vaapi-driver}/lib/dri";
    };

    extraOptions = [
      "--device=/dev/dri:/dev/dri"
    ];
  };
}
