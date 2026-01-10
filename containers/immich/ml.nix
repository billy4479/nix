{ ... }:
let
  baseHDDDir = "/mnt/HDD/apps/immich";
  version = "v2";
in
{
  nerdctl-containers.immich-machine-learning = {
    id = 128;
    imageToPull = "ghcr.io/immich-app/immich-machine-learning";
    volumes = [
      {
        hostPath = "${baseHDDDir}/model-cache";
        containerPath = "/cache";
      }
    ];
    environment = {
      IMMICH_VERSION = version;
    };
  };
}
