{ pkgs, lib, ... }:
let
  baseHDDDir = "/mnt/HDD/apps/immich";
  name = "immich-ml";
in
{
  nerdctl-containers.${name} = {
    id = 128;
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      copyToRoot = [
        pkgs.dockerTools.caCertificates
        pkgs.dockerTools.binSh
      ];

      config.entrypoint = [ (lib.getExe pkgs.immich-machine-learning) ];

    };
    volumes = [
      {
        hostPath = "${baseHDDDir}/model-cache";
        containerPath = "/cache";
      }
    ];
    environment = {
      MACHINE_LEARNING_CACHE_FOLDER = "/cache";

      HF_HOME = "/cache/hf";
      HF_HUB_CACHE = "/cache/hf/hub";
      HF_XET_CACHE = "/cache/hf/xet";

      MPLCONFIGDIR = "/cache/matplotlib";
    };
  };
}
