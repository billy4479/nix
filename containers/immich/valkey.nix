{ pkgs, lib, ... }:
let
  baseSSDDir = "/mnt/SSD/apps/immich";
  name = "immich-redis";
in
{
  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      config = {
        entrypoint = [ (lib.getExe' pkgs.valkey "valkey-server") ];
        cmd = [
          "--daemonize"
          "no"
          "--bind"
          "0.0.0.0"
          "--protected-mode"
          "no"
        ];
      };
    };
    volumes = [
      {
        hostPath = "${baseSSDDir}/valkey";
        containerPath = "/data";
      }
    ];
    id = 129;
  };
}
