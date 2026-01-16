{
  pkgs,
  extraPkgs,
  config,
  ...
}:
let
  name = "mc-runner";
  baseDir = "/mnt/SSD/apps/${name}";
  worldDir = "/mnt/SSD/minecraft/Friends-Git";
in
{
  sops.secrets.mc-runner-env = { };

  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      name = "mc-runner";
      tag = "nix-local";

      copyToRoot = [
        pkgs.dockerTools.caCertificates
        pkgs.restic
        extraPkgs.my-packages.mc-runner
        extraPkgs.my-packages.mc-java
      ];

      config.entrypoint = [ "/bin/mc-runner" ];
    };
    id = 13;

    environment = {
      DONT_LOAD_DOTENV = "yes";
      PORT = "4479";
      VITE_PORT = "5173";
      ENVIRONMENT = "debug";
      CONFIG_PATH = "/mc-runner/config.yml";
    };

    environmentFiles = [ config.sops.secrets.mc-runner-env.path ];

    ports = [
      "25565:25565/tcp"
      "19132:19132/udp"
      "19132:19132/tcp"
    ];

    volumes = [
      {
        hostPath = baseDir;
        containerPath = "/mc-runner";
      }
      {
        hostPath = worldDir;
        containerPath = "/world";
        userAccessible = true;
      }
      {
        hostPath = "${./config.yml}";
        containerPath = "/mc-runner/config.yml";
        readOnly = true;
      }
      {
        hostPath = "/mnt/HDD/apps/mc-runner/Friends-Git";
        containerPath = "/backup";
      }
    ];
  };
}
