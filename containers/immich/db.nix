{
  config,
  ...
}:
let
  baseSSDDir = "/mnt/SSD/apps/immich";
in
{
  nerdctl-containers."immich-database" = {
    imageToPull = "ghcr.io/immich-app/postgres";
    id = 130;

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
        hostPath = "${baseSSDDir}/db";
        containerPath = "/var/lib/postgresql/data";
      }
    ];
  };
}
