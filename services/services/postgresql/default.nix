{
  lib,
  options,
  pkgs,
  ...
}:
let
  name = "postgresql";
  id = 130;
  # Kept local (instead of reading config.nerdctl-containers) so this file
  # stays evaluable on hosts without the containers module.
  # Must match containers/module.nix: uid = 5000 + id, gid = 5000.
  uid = 5000 + id;
  gid = 5000;
  dataDir = "/mnt/SSD/apps/postgresql/18";
  containerDataDir = "/var/lib/postgresql/data";

  postgresqlVersion = "18.6";
  # 0.8.7 (2026-10-01) is a bug-fix patch release over 0.8.6: IVFFlat build
  # buffer overflow and an avg() aggregate error; no API or storage changes.
  pgvectorVersion = "0.8.7";
  vectorchordVersion = "1.1.1";
  expectedExtensions = "cube:1.5,earthdistance:1.2,pg_trgm:1.6,unaccent:1.1,uuid-ossp:1.1,vchord:${vectorchordVersion},vector:${pgvectorVersion}";

  postgresql = pkgs.postgresql_18.withPackages (extensions: [
    extensions.pgvector
    extensions.vectorchord
  ]);

  localeArchive = "${pkgs.glibcLocales}/lib/locale/locale-archive";
  postgresqlConfig = toString ./postgresql.conf;
  postgresqlHba = toString ./pg_hba.conf;

  fakeNss = pkgs.dockerTools.fakeNss.override {
    extraPasswdLines = [ "postgres:x:${toString uid}:${toString gid}:PostgreSQL:/tmp:/bin/sh" ];
    extraGroupLines = [ "containers:x:${toString gid}:postgres" ];
  };

  entrypoint = pkgs.writeShellApplication {
    name = "postgresql-entrypoint";
    runtimeInputs = [
      pkgs.coreutils
      postgresql
    ];
    text = # sh
      ''
        pgdata="''${PGDATA:-${containerDataDir}}"

        if [ ! -f "$pgdata/PG_VERSION" ]; then
          echo "Refusing to start PostgreSQL: $pgdata/PG_VERSION does not exist." >&2
          echo "Initialize the cluster explicitly with postgresql-init.service." >&2
          exit 1
        fi

        data_version=$(tr -d '[:space:]' < "$pgdata/PG_VERSION")
        if [ "$data_version" != "18" ]; then
          echo "Refusing to start PostgreSQL 18 with data directory version $data_version." >&2
          exit 1
        fi

        exec postgres -D "$pgdata" -c config_file=/etc/postgresql/postgresql.conf
      '';
  };

  init = pkgs.writeShellApplication {
    name = "postgresql-init";
    runtimeInputs = [
      pkgs.coreutils
      postgresql
    ];
    text = # sh
      ''
        if [ -e "${dataDir}/PG_VERSION" ]; then
          echo "Refusing to initialize PostgreSQL: ${dataDir}/PG_VERSION already exists." >&2
          exit 1
        fi

        if [ -n "$(ls -A "${dataDir}")" ]; then
          echo "Refusing to initialize PostgreSQL: ${dataDir} is not empty." >&2
          exit 1
        fi

        exec initdb \
          --pgdata="${dataDir}" \
          --username=postgres \
          --encoding=UTF8 \
          --locale=en_US.UTF-8 \
          --data-checksums \
          --auth-local=peer \
          --auth-host=scram-sha-256
      '';
  };

  image = pkgs.nix-snapshotter.buildImage {
    inherit name;
    tag = "nix-local";

    copyToRoot = [
      pkgs.dockerTools.binSh
      entrypoint
      fakeNss
      pkgs.glibcLocales
      postgresql
    ];

    config.entrypoint = [ (lib.getExe entrypoint) ];
  };

  test = pkgs.callPackage ./test.nix {
    inherit
      expectedExtensions
      localeArchive
      postgresql
      ;
  };
in
{
  # The database relies on optimistic overcommit for its memory accounting.
  boot.kernel.sysctl."vm.overcommit_memory" = lib.mkIf (options ? nerdctl-containers) 1;

  polpetta.services.${name} = {
    container = {
      inherit id;

      imageToBuild = image;

      environment = {
        PGDATA = containerDataDir;
        HOME = "/tmp";
        LANG = "en_US.UTF-8";
        LC_ALL = "en_US.UTF-8";
        LOCALE_ARCHIVE = localeArchive;
        PATH = "/bin";
      };

      volumes = [
        {
          hostPath = dataDir;
          containerPath = containerDataDir;
        }
        {
          hostPath = postgresqlConfig;
          containerPath = "/etc/postgresql/postgresql.conf";
          readOnly = true;
        }
        {
          hostPath = postgresqlHba;
          containerPath = "/etc/postgresql/pg_hba.conf";
          readOnly = true;
        }
      ];

      extraOptions = [
        "--read-only"
        "--shm-size=128m"
      ];
      stopTimeout = 120;
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

  assertions = lib.mkIf (options ? nerdctl-containers) [
    {
      assertion = pkgs.postgresql_18.version == postgresqlVersion;
      message = "Review the PostgreSQL migration before changing PostgreSQL ${postgresqlVersion}.";
    }
    {
      assertion = pkgs.postgresql18Packages.pgvector.version == pgvectorVersion;
      message = "Review Immich compatibility before changing pgvector ${pgvectorVersion}.";
    }
    {
      assertion = pkgs.postgresql18Packages.vectorchord.version == vectorchordVersion;
      message = "Review Immich compatibility before changing VectorChord ${vectorchordVersion}.";
    }
  ];

  systemd.services.postgresql-init = lib.mkIf (options ? nerdctl-containers) {
    description = "Explicitly initialize the PostgreSQL 18 data directory";
    path = [ postgresql ];
    environment = {
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
      LOCALE_ARCHIVE = localeArchive;
    };
    serviceConfig = {
      Type = "oneshot";
      User = "container-${toString uid}";
      Group = "containers";
      UMask = "0077";
      ExecStart = lib.getExe init;
    };
    unitConfig.RequiresMountsFor = dataDir;
  };

  systemd.services."nerdctl-${name}" = lib.mkIf (options ? nerdctl-containers) {
    postStart = # sh
      ''
        missing_container_attempts=0
        until ${lib.getExe pkgs.nerdctl} \
          --address /run/containerd/containerd.sock \
          --namespace default \
          exec ${name} /bin/pg_isready \
          --host=/tmp \
          --username=postgres \
          --dbname=postgres; do
          if ${lib.getExe pkgs.nerdctl} \
            --address /run/containerd/containerd.sock \
            --namespace default \
            inspect ${name} >/dev/null 2>&1; then
            missing_container_attempts=0
          else
            missing_container_attempts=$((missing_container_attempts + 1))
            if [ "$missing_container_attempts" -ge 10 ]; then
              echo "PostgreSQL container exited before becoming ready" >&2
              exit 1
            fi
          fi

          ${lib.getExe' pkgs.coreutils "sleep"} 1
        done
      '';
    serviceConfig.TimeoutStartSec = "infinity";
    unitConfig.RequiresMountsFor = dataDir;
  };

  systemd.tmpfiles.rules = lib.mkIf (options ? nerdctl-containers) [
    "d ${dataDir} 0700 container-${toString uid} containers - -"
  ];

  environment.systemPackages = lib.mkIf (options ? nerdctl-containers) [ pkgs.rsync ];

  system.build = lib.mkIf (options ? nerdctl-containers) {
    postgresqlImage = image;
    postgresqlPackage = postgresql;
    postgresqlTest = test;
  };
}
