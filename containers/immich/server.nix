{
  pkgs,
  config,
  ...
}:
let
  baseHDDDir = "/mnt/HDD/apps/immich";

  version = "v2";
  uploadLocation = "${baseHDDDir}/upload";

  inherit (import ../utils.nix { inherit pkgs config; }) makeContainer;
in
makeContainer {
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
}
