{ pkgs, config, ... }:
let
  inherit ((import ./utils.nix) { inherit pkgs config; }) makeContainer;

  name = "jackett";
  configDir = "/mnt/SSD/apps/${name}/config";
  downloadsDir = "/mnt/SSD/apps/${name}/downloads";
in
makeContainer {
  inherit name;
  image = "lscr.io/linuxserver/jackett";
  id = 8;

  environment = {
    "PGID" = "5000";
    "PUID" = "5000";
  };
  volumes = [
    {
      hostPath = downloadsDir;
      containerPath = "/downloads";
      userAccessible = true;
    }
    {
      hostPath = configDir;
      containerPath = "/config";
    }
  ];
  runByUser = false; # TODO: remove
}
