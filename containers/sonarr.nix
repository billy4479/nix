{ pkgs, lib, ... }:
let
  name = "sonarr";
  baseHDDDir = "/mnt/HDD/torrent";
  configDir = "/mnt/SSD/apps/${name}";
in
{
  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      config = {
        env = [
          "XDG_CONFIG_HOME=/config"
        ];
        entrypoint = [ (lib.getExe pkgs.radarr) ];
        cmd = [
          "-nobrowser"
          "-data=/config"
        ];
      };

      copyToRoot = with pkgs.dockerTools; [
        caCertificates
        (pkgs.writeTextDir "/etc/passwd" "container-5009:x:5009:5000:User for container sonarr:/var/empty:/run/current-system/sw/bin/nologin")
      ];
    };
    id = 9;

    volumes = [
      {
        hostPath = baseHDDDir;
        containerPath = "/data";
        userAccessible = true;
      }
      {
        hostPath = configDir;
        containerPath = "/config";
      }
    ];
  };
}
