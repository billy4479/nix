{ pkgs, lib, ... }:
let
  baseSSDDir = "/mnt/SSD/apps/outline";
in
{
  polpetta.services.outline-valkey = {
    container = {
      imageToBuild = pkgs.nix-snapshotter.buildImage {
        name = "outline-valkey";
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
      id = 133;
    };

    # The listen port is implicit in the valkey image; declare it so it can
    # be probed. local raw ports are never tunneled.
    raw = [
      {
        port = 6379;
        access = "local";
        probe.enable = true;
      }
    ];
  };
}
