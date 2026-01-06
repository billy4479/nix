{
  pkgs,
  lib,
  config,
  ...
}:
let
  baseHDDDir = "/mnt/HDD/apps/immich";
  baseSSDDir = "/mnt/SSD/apps/immich";

  version = "v2";
  uploadLocation = "${baseHDDDir}/upload";
  modelCacheLocation = "${baseHDDDir}/model-cache";
  dbLocation = "${baseSSDDir}/db";
  valkeyLocation = "${baseSSDDir}/valkey";

  inherit (import ./utils.nix { inherit pkgs config; }) makeContainer;
in
{
  sops.secrets.immichEnv = { };
  boot.kernel.sysctl = {
    "vm.overcommit_memory" = 1;
  };
}
//
  lib.recursiveUpdate
    (lib.recursiveUpdate
      (makeContainer {
        name = "immich-server";
        image = "ghcr.io/immich-app/immich-server";
        id = 3;
        volumes = [
          {
            hostPath = uploadLocation;
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
          config.sops.secrets.immichEnv.path
        ];
        environment = {
          # TODO: determine which one are superfluous
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "immich";
          POSTGRES_INITDB_ARGS = "--data-checksums";

          DB_USERNAME = "postgres";
          DB_DATABASE_NAME = "immich";

          DB_HOSTNAME = "10.0.1.130";
          REDIS_HOSTNAME = "10.0.1.129";
          IMMICH_VERSION = version;
          IMMICH_MACHINE_LEARNING_URL = "http://10.0.1.128:3003";
        };
        dependsOn = [
          "immich-redis"
          "immich-database"
        ];
      })
      (makeContainer {
        name = "immich-machine-learning";
        id = 128;
        image = "ghcr.io/immich-app/immich-machine-learning";
        volumes = [
          {
            hostPath = modelCacheLocation;
            containerPath = "/cache";
          }
        ];
        environment = {
          IMMICH_VERSION = version;
        };
      })
    )
    (
      lib.recursiveUpdate
        (makeContainer {
          name = "immich-redis";
          image = "docker.io/valkey/valkey";
          volumes = [
            {
              hostPath = valkeyLocation;
              containerPath = "/data";
            }
          ];
          id = 129;
        })
        (makeContainer {
          name = "immich-database";
          image = "ghcr.io/immich-app/postgres";
          environmentFiles = [
            config.sops.secrets.immichEnv.path
          ];
          environment = {
            POSTGRES_USER = "postgres";
            POSTGRES_DB = "immich";
            POSTGRES_INITDB_ARGS = "--data-checksums";
          };
          volumes = [
            {
              hostPath = dbLocation;
              containerPath = "/var/lib/postgresql/data";
            }
          ];
          id = 130;
        })
    )
