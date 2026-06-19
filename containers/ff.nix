{
  pkgs,
  ...
}:
let
  name = "ff";
  baseDir = "/mnt/SSD/apps/${name}";
in
{
  nerdctl-containers.${name} = {
    id = 17;
    useNginx = true;
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      copyToRoot = with pkgs; [
        dockerTools.caCertificates
        ff
      ];

      config.entrypoint = [ "/bin/ff" ];
    };

    environment = {
      PORT = "4479";
      ENVIRONMENT = "production";
      ORIGIN = "https://ff.internal.polpetta.online";
      FF_DATA_PATH = "/data";
    };

    volumes = [
      {
        hostPath = baseDir;
        containerPath = "/data";
      }
    ];
  };
}
