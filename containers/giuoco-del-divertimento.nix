{
  pkgs,
  ...
}:
let
  name = "giuoco-del-divertimento";
  baseDir = "/mnt/SSD/apps/${name}";
in
{
  nerdctl-containers.${name} = {
    id = 18;
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      copyToRoot = with pkgs; [
        dockerTools.caCertificates
        giuoco-del-divertimento
      ];

      config.entrypoint = [ "/bin/giuoco-del-divertimento" ];
    };

    environment = {
      PORT = "4479";
      ENVIRONMENT = "production";
      ORIGIN = "https://giuoco-del-divertimento.internal.polpetta.online";
      DATABASE_URL = "/data/items.db";
    };

    volumes = [
      {
        hostPath = baseDir;
        containerPath = "/data";
      }
    ];
  };
}
