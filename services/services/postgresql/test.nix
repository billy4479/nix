{
  pkgs,
  postgresql,
  localeArchive,
  expectedExtensions,
}:
pkgs.runCommand "postgresql-immich-extension-test"
  {
    nativeBuildInputs = [ postgresql ];
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    LOCALE_ARCHIVE = localeArchive;
  }
  # sh
  ''
    export HOME="$TMPDIR"
    dataDir="$TMPDIR/data"
    socketDir="$TMPDIR/socket"
    mkdir "$socketDir"

    initdb \
      --pgdata="$dataDir" \
      --username=postgres \
      --encoding=UTF8 \
      --locale=en_US.UTF-8 \
      --data-checksums \
      --auth-local=trust \
      --auth-host=scram-sha-256 >/dev/null

    pg_ctl \
      --pgdata="$dataDir" \
      --log="$TMPDIR/postgresql.log" \
      --options="-c listen_addresses= -c unix_socket_directories=$socketDir -c shared_preload_libraries=vchord.so" \
      start >/dev/null
    trap 'pg_ctl --pgdata="$dataDir" stop --mode=fast >/dev/null' EXIT

    psql --host="$socketDir" --username=postgres --dbname=postgres \
      --set=ON_ERROR_STOP=1 <<'SQL'
    CREATE EXTENSION vchord CASCADE;
    CREATE EXTENSION earthdistance CASCADE;
    CREATE EXTENSION pg_trgm;
    CREATE EXTENSION unaccent;
    CREATE EXTENSION "uuid-ossp";
    SQL

    test "$(psql --host="$socketDir" --username=postgres --dbname=postgres --tuples-only --no-align \
      --command="SELECT string_agg(extname || ':' || extversion, ',' ORDER BY extname) FROM pg_extension WHERE extname <> 'plpgsql'")" = "${expectedExtensions}"
    test "$(psql --host="$socketDir" --username=postgres --dbname=postgres --tuples-only --no-align \
      --command="SHOW data_checksums")" = "on"
    test "$(psql --host="$socketDir" --username=postgres --dbname=postgres --tuples-only --no-align \
      --command="SHOW shared_preload_libraries")" = "vchord.so"

    touch "$out"
  ''
