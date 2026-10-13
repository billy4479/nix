{
  config,
  lib,
  options,
  ...
}:
let
  baseSSDDir = "/mnt/SSD/apps/immich";
in
{
  sops.secrets.immichEnv = lib.mkIf (options ? nerdctl-containers) { };

  # The database depends on optimistic overcommit for its memory accounting.
  boot.kernel.sysctl."vm.overcommit_memory" = lib.mkIf (options ? nerdctl-containers) 1;

  polpetta.services.immich-database = {
    container = {
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

    # The listen port is implicit in the postgres image; declare it so it can
    # be probed. local raw ports are never tunneled.
    raw = [
      {
        port = 5432;
        access = "local";
        probe.enable = true;
      }
    ];
  };
}
