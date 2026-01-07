{
  pkgs,
  config,
  ...
}:
let
  baseSSDDir = "/mnt/SSD/apps/immich";
  dbLocation = "${baseSSDDir}/db";

  inherit (import ../utils.nix { inherit pkgs config; }) makeContainer;
in
makeContainer {
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
}
