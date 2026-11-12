{ pkgs, lib, ... }:
let
  baseSSDDir = "/mnt/SSD/apps/outline";
in
{
  polpetta.services.outline-valkey = {
    container = {
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
        allowedSources = [ "10.0.1.24/32" ];
        probe.enable = true;
      }
    ];
  };
}
