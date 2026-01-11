{ pkgs, lib, ... }:
let
  name = "cloudflared";
  baseSSDDir = "/mnt/SSD/apps/${name}";
in
{
  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";
      config.entrypoint = [ (lib.getExe pkgs.cloudflared) ];
    };
    id = 131;

    volumes = [
      {
        hostPath = baseSSDDir;
        containerPath = "/etc/cloudflared";
      }
    ];

    cmd = [
      "tunnel"
      "run"
      "nas"
    ];
  };
}
