{ config, ... }:
let
  baseHDDDir = "/mnt/HDD/apps/immich";
  baseSSDDir = "/mnt/SSD/apps/immich";

  version = "v2.1.0";
  uploadLocation = "${baseHDDDir}/upload";
  modelCacheLocation = "${baseHDDDir}/model-cache";
  dbLocation = "${baseSSDDir}/db";
  valkeyLocation = "${baseSSDDir}/valkey";

  inherit (import ./utils.nix) setCommonContainerConfig;
in
{
  sops.secrets.immichEnv = { };

  virtualisation.oci-containers.containers = {
    immich-server = {
      image = "ghcr.io/immich-app/immich-server:${version}";
      ports = [ "2283:2283" ];
      volumes = [
        "${uploadLocation}:/usr/src/app/upload"
        "/etc/localtime:/etc/localtime:ro"

        "/mnt/HDD/generic/Giacomo/Archive/Foto Jack:/mnt/media/Foto Jack Archivio:ro"
        "/mnt/HDD/generic/Edo/foto - edo - archivio:/mnt/media/Foto Edo Archivio:ro"
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
        TZ = "Europe/Rome";
      };
      dependsOn = [
        "immich-redis"
        "immich-database"
      ];
    }
    // (setCommonContainerConfig {
      ip = "10.0.1.3";
      autoUpdate = false;
    });

    immich-machine-learning = {
      image = "ghcr.io/immich-app/immich-machine-learning:${version}";
      volumes = [ "${modelCacheLocation}:/cache" ];
      environment = {
        IMMICH_VERSION = version;
      };
    }
    // (setCommonContainerConfig {
      ip = "10.0.1.128";
      autoUpdate = false;
    });

    immich-redis = {
      image = "docker.io/valkey/valkey:8-alpine";
      volumes = [ "${valkeyLocation}:/data" ];
    }
    // (setCommonContainerConfig {
      ip = "10.0.1.129";
      autoUpdate = false;
    });

    immich-database = {
      image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0";
      environmentFiles = [
        config.sops.secrets.immichEnv.path
      ];
      environment = {
        POSTGRES_USER = "postgres";
        POSTGRES_DB = "immich";
        POSTGRES_INITDB_ARGS = "--data-checksums";
      };
      volumes = [ "${dbLocation}:/var/lib/postgresql/data" ];
    }
    // (setCommonContainerConfig {
      ip = "10.0.1.130";
      autoUpdate = false;
    });
  };

  # For valkey
  boot.kernel.sysctl = {
    "vm.overcommit_memory" = 1;
  };
}
