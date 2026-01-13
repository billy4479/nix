{ pkgs, lib, ... }:
let
  name = "flaresolverr";
  baseSSDDir = "/mnt/SSD/apps/${name}";
in
{
  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      config = {
        Env = [ "HOME=/app" ];
        EntryPoint = [ (lib.getExe pkgs.flaresolverr) ];
        WorkingDir = "/app";
      };
    };
    id = 133;

    environment = {
      "LOG_LEVEL" = "info";
    };

    volumes = [
      {
        hostPath = "${baseSSDDir}/local";
        containerPath = "/app/.local";
      }
    ];

    tmpfs = [
      "/tmp"
      "/app/.cache"
    ];
  };
}
