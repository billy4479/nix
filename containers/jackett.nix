{ pkgs, lib, ... }:
let
  name = "jackett";
  configDir = "/mnt/SSD/apps/${name}/config";
  downloadsDir = "/mnt/SSD/apps/${name}/downloads";
in
{
  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      config = {
        env = [
          "XDG_DATA_HOME=/config"
          "XDG_CONFIG_HOME=/config"
        ];
        entrypoint = [ (lib.getExe pkgs.jackett) ];
      };

      copyToRoot = with pkgs.dockerTools; [
        caCertificates
      ];
    };

    id = 8;

    volumes = [
      {
        hostPath = downloadsDir;
        containerPath = "/downloads";
      }
      {
        hostPath = configDir;
        containerPath = "/config";
      }
    ];
  };
}
