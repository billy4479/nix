{ pkgs, lib, ... }:
let
  name = "radarr";
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
        (pkgs.writeTextDir "/etc/passwd" "container-5007:x:5007:5000:User for container radarr:/var/empty:/run/current-system/sw/bin/nologin")
      ];
    };
    id = 7;

    volumes = [
      {
        hostPath = baseHDDDir;
        containerPath = "/data";
      }
      {
        hostPath = configDir;
        containerPath = "/config";
      }
    ];
  };
}
