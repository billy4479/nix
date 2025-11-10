{ pkgs, config, ... }:
let
  name = "flaresolverr";
  baseSSDDir = "/mnt/SSD/apps/${name}";
  inherit (import ./utils.nix { inherit pkgs config; }) makeContainer;
in
makeContainer {
  inherit name;
  image = "ghcr.io/flaresolverr/flaresolverr";
  ip = "10.0.1.133";

  environment = {
    "LOG_LEVEL" = "info";
  };

  volumes = [
    "${baseSSDDir}/local:/app/.local:rw"
  ];
  adminOnlyDirs = [ baseSSDDir ];

  tmpfs = [
    "/tmp"
    "/app/.cache"
  ];
}
