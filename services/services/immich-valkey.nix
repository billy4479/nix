{ pkgs, lib, ... }:
let
  baseSSDDir = "/mnt/SSD/apps/immich";
in
{
  polpetta.services.immich-valkey = {
    container = {
      imageToBuild = pkgs.nix-snapshotter.buildImage {
        name = "immich-valkey";
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
            "--dir"
            "/data"
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
  };
}
