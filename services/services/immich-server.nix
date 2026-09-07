{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  name = "immich-server";
  baseHDDDir = "/mnt/HDD/apps/immich";
in
{
  sops.secrets.immichAppEnv = lib.mkIf (options ? nerdctl-containers) {
    restartUnits = [ "nerdctl-${name}.service" ];
  };

  polpetta.services.${name} = {
    container = {
      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";

        copyToRoot = [
          pkgs.dockerTools.caCertificates
          pkgs.coreutils
        ];

        config.entrypoint = [ (lib.getExe pkgs.immich) ];
      };

      id = 3;
      volumes = [
        {
          hostPath = "${baseHDDDir}/upload";
          containerPath = "/usr/src/app/upload";
        }
        {
          hostPath = "/etc/localtime";
          containerPath = "/etc/localtime";
          readOnly = true;
        }
        {
          hostPath = "/mnt/HDD/generic/Giacomo/Archive/Foto Jack";
          containerPath = "/mnt/media/Foto Jack Archivio";
          readOnly = true;
        }
        {
          hostPath = "/mnt/HDD/generic/Edo/foto - edo - archivio";
          containerPath = "/mnt/media/Foto Edo Archivio";
          readOnly = true;
        }
      ];
      environmentFiles = [
        config.sops.secrets.immichAppEnv.path
      ];
      environment = {
        DB_USERNAME = "immich";
        DB_DATABASE_NAME = "immich";
        DB_PORT = "5432";

        DB_HOSTNAME = "10.0.1.130";
        REDIS_HOSTNAME = "10.0.1.129";
        REDIS_PORT = "6379";

        IMMICH_HOST = "0.0.0.0";
        IMMICH_PORT = "2283";
        IMMICH_MEDIA_LOCATION = "/usr/src/app/upload";
        IMMICH_BUILD_DATA = "${pkgs.immich}/lib/node_modules/immich/build";
        IMMICH_MACHINE_LEARNING_URL = "http://10.0.1.128:3003";

        PATH = lib.makeBinPath [
          pkgs.coreutils
          pkgs.jellyfin-ffmpeg
        ];
        FFMPEG_PATH = lib.getExe pkgs.jellyfin-ffmpeg;
        FFPROBE_PATH = lib.getExe' pkgs.jellyfin-ffmpeg "ffprobe";
      };
      dependsOn = [
        "immich-redis"
        "postgresql"
        "immich-ml"
      ];
    };

    web = {
      port = 2283;
      access = "tailnet";
      # Historical domain: the UI is served under `immich`, not the container
      # name.
      domain = "immich.internal.polpetta.online";
      nginx.extraConfig = ''
        client_max_body_size 50000M;
        proxy_request_buffering off;
        proxy_read_timeout 3600;
        send_timeout 3600;
      '';
    };
  };
}
