{ pkgs, config, ... }:
let
  inherit ((import ./utils.nix) { inherit pkgs config; }) makeContainer;

  name = "jellyfin";
  baseHDDDir = "/mnt/HDD/torrent";
  baseSSDDir = "/mnt/SSD/apps/${name}";
in
makeContainer {
  inherit name;
  image = "docker.io/jellyfin/jellyfin";
  id = 10;

  volumes = [
    {
      hostPath = baseHDDDir;
      containerPath = "/media";
      userAccessible = true;
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
}
