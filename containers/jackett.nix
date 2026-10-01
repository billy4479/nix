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
    useNginx = true;
    dependsOn = [ "byparr" ];

    # Jackett's self-updater cannot install updates over the read-only nix
    # store, but still downloads and extracts each new release into /tmp:
    # it once accumulated >1GB of tmpfs. Updates are disabled in
    # ServerConfig.json; the default tmpfs cap bounds any future leak.

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
