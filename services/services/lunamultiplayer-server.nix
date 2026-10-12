{ pkgs, ... }:
let
  name = "lunamultiplayer-server";
  baseDir = "/mnt/SSD/apps/${name}";
in
{
  polpetta.services.${name} = {
    container = {
      id = 20;

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

      extraOptions = [ "--stop-signal=SIGINT" ];

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

    web = {
      port = 8900;
      access = "tailnet";
      # Historical domain: the status UI is served under `lunamultiplayer`, not
      # the container name.
      domain = "lunamultiplayer.internal.polpetta.online";
    };

    raw = [
      { port = 8800; proto = "udp"; access = "public"; } # game traffic
    ];
  };
}
