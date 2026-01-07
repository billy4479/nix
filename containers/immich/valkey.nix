{
  pkgs,
  config,
  ...
}:
let
  baseSSDDir = "/mnt/SSD/apps/immich";
  valkeyLocation = "${baseSSDDir}/valkey";

  inherit (import ../utils.nix { inherit pkgs config; }) makeContainer;
in
makeContainer {
  name = "immich-redis";
  image = "docker.io/valkey/valkey";
  volumes = [
    {
      hostPath = valkeyLocation;
      containerPath = "/data";
    }
  ];
  id = 129;
}
