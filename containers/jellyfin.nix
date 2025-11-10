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
  ip = "10.0.1.8";

  volumes = [
    "${baseHDDDir}:/media:rw"
    "${baseSSDDir}/config:/config:rw"
    "${baseSSDDir}/cache:/cache:rw"
  ];
  adminOnlyDirs = [ baseSSDDir ];
  userDirs = [ baseHDDDir ];

  extraOptions = [
    "--device=/dev/dri:/dev/dri"
  ];
}
