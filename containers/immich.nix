{ config, ... }:
let
  baseHDDDir = "/mnt/HDD/apps/immich";
  baseSSDDir = "/mnt/SSD/apps/immich";

  version = "v2.0.1";
  uploadLocation = "${baseHDDDir}/upload";
  modelCacheLocation = "${baseHDDDir}/model-cache";
  dbLocation = "${baseSSDDir}/db";
  valkeyLocation = "${baseSSDDir}/valkey";
in
{
  sops.secrets.immichEnv = { };

  virtualisation.oci-containers.containers = {
    immich-server = {
      autoStart = true;
      user = "5000:5000";

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
        POSTGRES_USER = "postgres";
        POSTGRES_DB = "immich";
        POSTGRES_INITDB_ARGS = "--data-checksums";
      };
      environment = {
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
      extraOptions = [ "--ip=10.0.1.3" ];
    };

    immich-machine-learning = {
      autoStart = true;
      user = "5000:5000";

      image = "ghcr.io/immich-app/immich-machine-learning:${version}";
      volumes = [ "${modelCacheLocation}:/cache" ];
      environment = {
        IMMICH_VERSION = version;
      };
      extraOptions = [ "--ip=10.0.1.128" ];
    };

    immich-redis = {
      autoStart = true;
      user = "5000:5000";

      image = "docker.io/valkey/valkey:8-alpine";
      volumes = [ "${valkeyLocation}:/data" ];
      extraOptions = [
        "--health-cmd=redis-cli ping || exit 1"
        "--ip=10.0.1.129"
      ];
    };

    immich-database = {
      autoStart = true;
      user = "5000:5000";

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
      extraOptions = [ "--ip=10.0.1.130" ];
    };
  };

  # For valkey
  boot.kernel.sysctl = {
    "vm.overcommit_memory" = 1;
  };
}
