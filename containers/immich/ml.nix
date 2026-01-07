{
  pkgs,
  config,
  ...
}:
let
  baseHDDDir = "/mnt/HDD/apps/immich";

  version = "v2";
  modelCacheLocation = "${baseHDDDir}/model-cache";
  inherit (import ../utils.nix { inherit pkgs config; }) makeContainer;
in
makeContainer {
  name = "immich-machine-learning";
  id = 128;
  image = "ghcr.io/immich-app/immich-machine-learning";
  volumes = [
    {
      hostPath = modelCacheLocation;
      containerPath = "/cache";
    }
  ];
  environment = {
    IMMICH_VERSION = version;
  };
}
