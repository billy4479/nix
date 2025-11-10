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
  ip = "10.0.1.8";

  environment = {
    "PGID" = "5000";
    "PUID" = "5000";
  };
  volumes = [
    "${downloadsDir}:/downloads:rw"
    "${configDir}:/config:rw"
  ];
  runByUser = false; # TODO: remove

  adminOnlyDirs = [ configDir ];
  userDirs = [ downloadsDir ];
}
