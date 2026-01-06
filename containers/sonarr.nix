{ pkgs, config, ... }:
let
  inherit ((import ./utils.nix) { inherit pkgs config; }) makeContainer;

  name = "sonarr";
  baseHDDDir = "/mnt/HDD/torrent";
  configDir = "/mnt/SSD/apps/${name}";
in
makeContainer {
  inherit name;
  image = "lscr.io/linuxserver/sonarr";
  ip = "10.0.1.9";

  runByUser = false; # TODO: remove
  environment = {
    "PGID" = "5000";
    "PUID" = "5000";
  };

  volumes = [
    {
      hostPath = baseHDDDir;
      containerPath = "/data";
      userAccessible = true;
    }
    {
      hostPath = configDir;
      containerPath = "/config";
    }
  ];
}
