{ pkgs, ... }:
let
  name = "lunamultiplayer-server";
  baseDir = "/mnt/SSD/apps/${name}";
in
{
  nerdctl-containers.${name} = {
    id = 20;
    useNginx = true;

    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      copyToRoot = with pkgs; [
        dockerTools.caCertificates
        lunamultiplayer-server
      ];

      config.entrypoint = [ "/bin/Server" ];
    };

    environment = {
      # The nix package patches Luna to store Config, Universe, Plugins and logs
      # under this directory instead of the immutable package directory.
      LUNAMULTIPLAYER_DIR = "/data";
    };

    # Recommended generated config values:
    # Config/ConnectionSettings.xml: Port = 8800, Upnp = false
    # Config/WebsiteSettings.xml: EnableWebsite = true, Port = 8900
    volumes = [
      {
        hostPath = baseDir;
        containerPath = "/data";
      }
    ];
  };
}
