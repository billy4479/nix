{ ... }:
let
  baseSSDDir = "/mnt/SSD/apps/immich";
in
{
  nerdctl-containers."immich-redis" = {
    imageToPull = "docker.io/valkey/valkey";
    volumes = [
      {
        hostPath = "${baseSSDDir}/valkey";
        containerPath = "/data";
      }
    ];
    id = 129;
  };
}
