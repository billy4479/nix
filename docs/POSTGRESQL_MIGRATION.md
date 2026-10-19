# PostgreSQL 18 migration

This runbook migrates Immich from the existing PostgreSQL 14 cluster to the
custom PostgreSQL 18 container. It also changes Immich from the `postgres`
superuser to a dedicated non-superuser role.

The migration is intentionally a logical dump and restore. PostgreSQL 18 never
opens the PostgreSQL 14 data directory, which remains the primary rollback
mechanism.

## Target state

- PostgreSQL 18.6 with pgvector 0.8.7 and VectorChord 1.1.1.
- Container `postgresql` at `10.0.1.130`, running as UID/GID `5130:5000`.
- PostgreSQL 18 data in `/mnt/SSD/apps/postgresql/18`.
- The old PostgreSQL 14 data remains in `/mnt/SSD/apps/immich/db`.
- Immich connects as the non-superuser role `immich`.
- PostgreSQL administration uses local peer authentication through
  `nerdctl exec` and does not require a network-accessible superuser password.
- Network authentication permits only the `immich` role, database, and
  container address. Add similarly narrow rules when adding other applications.

Do not remove, rename, copy, or otherwise modify the PostgreSQL 14 data
directory during this procedure.

## Stop conditions

Stop the migration and investigate if any of these conditions occur:

- The source database reports checksum failures.
- The source has the legacy `vectors` extension. Immich 3 must be fully migrated
  to VectorChord before continuing.
- The source has an extension that is unavailable in the PostgreSQL 18 package.
- The logical dump cannot be listed successfully.
- Either required ZFS snapshot is missing.
- The PostgreSQL 18 extension test or system build fails.
- The restore command returns a nonzero status.
- Source and target row counts differ.
- Restored indexes are invalid or application objects have the wrong owner.
- Immich reports a database migration, extension, or permission error.

## 1. Prepare the configuration and secret

Generate a new password for the `immich` database role:

```sh
openssl rand -hex 32
```

In the secrets repository, replace the flat `immichEnv` dotenv with a new
hierarchical key named `db-password` under an `immich` section, holding the new
password (the same style as the `grafana` section). The dotenv holds nothing
else: `POSTGRES_PASSWORD` is obsolete because the new superuser has no network
password, and the old `DB_PASSWORD` applied to the `postgres` role. Do not
commit plaintext credentials.

Preserve the old secrets revision for rollback, update the flake lock to the new
secrets revision, and do not deploy yet.

Disable Immich's automatic database-backup schedule before the migration. This
deployment deliberately uses the operator-run logical backups documented below;
do not rely on the built-in job unless it is separately validated with the
non-superuser role and all required client binaries.

## 2. Validate locally

Run these commands from the repository without deploying:

```sh
nix eval .#nixosConfigurations.serverone.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.vps-proxy.config.system.build.toplevel.drvPath
nix eval .#homeConfigurations."billy@computerone".activationPackage.drvPath
nix eval .#homeConfigurations."billy@portatilo".activationPackage.drvPath
nix build .#nixosConfigurations.serverone.config.system.build.postgresqlTest
nix build .#nixosConfigurations.serverone.config.system.build.postgresqlImage
nix build .#nixosConfigurations.serverone.config.system.build.toplevel
```

`nix flake check --no-build` is deliberately not listed: it is currently broken
by an unrelated home-manager evaluation issue (the konsole catppuccin module).
The evaluations above cover every system in the flake.

The PostgreSQL test initializes a disposable checksummed cluster, preloads
VectorChord, creates all extensions required by Immich, and verifies their
versions.

Before starting downtime, confirm that the previous NixOS system generation and
the old secrets revision remain available for rollback.

## 3. Inspect PostgreSQL 14

Run on `serverone` before downtime:

```sh
sudo nerdctl exec -i immich-database \
  psql -X -v ON_ERROR_STOP=1 -U postgres -d immich <<'SQL'
SELECT version();

SELECT datname, pg_get_userbyid(datdba) AS owner,
       pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
WHERE datname = 'immich';

SELECT rolname, rolsuper, rolcreatedb, rolcreaterole,
       rolreplication, rolbypassrls, rolcanlogin
FROM pg_roles
ORDER BY rolname;

SELECT extname, extversion, pg_get_userbyid(extowner) AS owner
FROM pg_extension
ORDER BY extname;

SHOW data_checksums;
SHOW shared_preload_libraries;
SHOW server_encoding;

SELECT datname, checksum_failures
FROM pg_stat_database
WHERE checksum_failures IS NOT NULL;
SQL
```

The expected extensions are `cube`, `earthdistance`, `pg_trgm`, `plpgsql`,
`unaccent`, `uuid-ossp`, `vchord`, and `vector`. Record any additional extension
because it must be installed in the target before restoring.

`SHOW shared_preload_libraries` reports `vchord.so, vectors.so` on the source:
the source image preloads `vectors.so` (the pgvecto.rs library) unconditionally.
The preload alone is not a stop condition. Only an installed `vectors`
*extension* is. Because the inventory above covers the `immich` database only,
check every database:

```sh
sudo nerdctl exec immich-database \
  psql -X -U postgres -d postgres -tAc \
  "SELECT datname FROM pg_database WHERE NOT datistemplate;" |
  while read -r db; do
    [ -n "$db" ] || continue
    echo "== $db =="
    sudo nerdctl exec immich-database \
      psql -X -U postgres -d "$db" -tAc \
      "SELECT extname FROM pg_extension ORDER BY 1;" < /dev/null
  done
```

Only `immich` is migrated; the other databases (`postgres`, `template0`,
`template1`) are recreated empty by `initdb` with their default `plpgsql` only.

Inspect authentication separately:

```sh
sudo nerdctl exec immich-database \
  psql -X -U postgres -d immich -c \
  "SELECT line_number, type, database, user_name, address, auth_method, error
   FROM pg_hba_file_rules
   ORDER BY line_number;"
```

## 4. Verify storage

Identify the actual ZFS datasets and check available space:

```sh
findmnt -no FSTYPE,SOURCE -T /mnt/SSD/apps/immich/db
findmnt -no FSTYPE,SOURCE -T /mnt/HDD/apps/immich/upload
sudo du -sh /mnt/SSD/apps/immich/db
df -h /mnt/SSD/apps /mnt/HDD/apps
sudo zfs list -o name,used,available,mountpoint
```

Both paths must be on ZFS. The SSD must have enough free space for the complete
old and new clusters plus temporary WAL and index construction. The HDD must
have enough space for the logical dump.

## 5. Begin downtime

Use one shell for the following commands so the variables remain set:

```sh
export MIGRATION_ID="$(date -u +%Y%m%dT%H%M%SZ)"
export BACKUP_DIR="/mnt/HDD/apps/postgresql/migrations/$MIGRATION_ID"
export DUMP="$BACKUP_DIR/immich.pg14.dump"

sudo install -d -m 0700 -o "$(id -u)" -g "$(id -g)" "$BACKUP_DIR"
umask 077
```

Prevent Immich from restarting during deployment, then stop it:

```sh
sudo systemctl mask --runtime nerdctl-immich-server.service
sudo systemctl stop nerdctl-immich-server.service
sudo systemctl is-active nerdctl-immich-server.service
```

The final command must report `inactive`.

Stop Immich's persistent Valkey queue at the same consistency boundary:

```sh
export VALKEY_SHUTDOWN_STARTED="$(date --iso-8601=seconds)"

sudo systemctl mask --runtime nerdctl-immich-redis.service
sudo nerdctl stop --time 120 immich-redis
sudo systemctl stop nerdctl-immich-redis.service
sudo systemctl is-active nerdctl-immich-redis.service

sudo journalctl \
  --unit=nerdctl-immich-redis.service \
  --since="$VALKEY_SHUTDOWN_STARTED" \
  --no-pager
```

The mask and explicit stop must succeed, `is-active` must report `inactive`, and
the journal must show Valkey completing its final save and exiting without a
forced kill. Keep Valkey stopped and masked until PostgreSQL 18 has been restored
and validated.

Confirm no sessions remain connected to the Immich database:

```sh
sudo nerdctl exec immich-database \
  psql -X -U postgres -d postgres -c \
  "SELECT pid, usename, application_name, client_addr, state
   FROM pg_stat_activity
   WHERE datname = 'immich';"
```

Do not continue until the query returns no sessions.

## 6. Record source database state

The application is stopped, so exact table counts, sequence positions, and
large-object counts can be compared after the restore:

```sh
sudo nerdctl exec -i immich-database \
  psql -X -q -v ON_ERROR_STOP=1 -U postgres -d immich \
  > "$BACKUP_DIR/source-database-state.csv" <<'SQL'
CREATE TEMP TABLE migration_state (
  object_type text,
  schema_name text,
  object_name text,
  value text
);

DO $body$
DECLARE
  relation record;
  count_result bigint;
  sequence_relation record;
  sequence_last_value bigint;
  sequence_is_called boolean;
BEGIN
  FOR relation IN
    SELECT schemaname, tablename
    FROM pg_tables
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
      AND schemaname NOT LIKE 'pg_temp_%'
      AND schemaname NOT LIKE 'pg_toast_temp_%'
    ORDER BY schemaname, tablename
  LOOP
    EXECUTE format(
      'SELECT count(*) FROM %I.%I',
      relation.schemaname,
      relation.tablename
    ) INTO count_result;

    INSERT INTO migration_state
    VALUES ('table', relation.schemaname, relation.tablename, count_result::text);
  END LOOP;

  FOR sequence_relation IN
    SELECT schemaname, sequencename
    FROM pg_sequences
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
      AND schemaname NOT LIKE 'pg_temp_%'
      AND schemaname NOT LIKE 'pg_toast_temp_%'
    ORDER BY schemaname, sequencename
  LOOP
    EXECUTE format(
      'SELECT last_value, is_called FROM %I.%I',
      sequence_relation.schemaname,
      sequence_relation.sequencename
    ) INTO sequence_last_value, sequence_is_called;

    INSERT INTO migration_state
    VALUES (
      'sequence',
      sequence_relation.schemaname,
      sequence_relation.sequencename,
      format('%s:%s', sequence_last_value, sequence_is_called)
    );
  END LOOP;
END
$body$;

INSERT INTO migration_state
VALUES (
  'large_object',
  'pg_catalog',
  'pg_largeobject_metadata',
  (SELECT count(*)::text FROM pg_largeobject_metadata)
);

\copy (SELECT * FROM migration_state ORDER BY object_type, schema_name, object_name) TO STDOUT WITH (FORMAT csv, HEADER true)
SQL
```

## 7. Create and inspect the dump

Create a custom-format dump without source ownership or grants:

```sh
sudo nerdctl exec immich-database \
  pg_dump \
  --username=postgres \
  --dbname=immich \
  --format=custom \
  --no-owner \
  --no-privileges \
  > "$DUMP"

test -s "$DUMP"
sha256sum "$DUMP" | tee "$DUMP.sha256"

sudo nerdctl exec -i immich-database \
  pg_restore --list < "$DUMP" \
  > "$BACKUP_DIR/restore.pg14.list"
```

Review `restore.pg14.list`. It must contain the expected tables, table data,
indexes, constraints, and extensions.

## 8. Stop PostgreSQL 14 and snapshot

Stop PostgreSQL cleanly:

```sh
export SHUTDOWN_STARTED="$(date --iso-8601=seconds)"

sudo systemctl mask --runtime nerdctl-immich-database.service
sudo nerdctl stop --time 120 immich-database
sudo systemctl stop nerdctl-immich-database.service
sudo systemctl is-active nerdctl-immich-database.service

sudo journalctl \
  --unit=nerdctl-immich-database.service \
  --since="$SHUTDOWN_STARTED" \
  --no-pager
```

The mask and explicit `nerdctl stop` must both succeed. The explicit stop gives
PostgreSQL up to two minutes to shut down cleanly instead of using nerdctl's
ten-second default. The
`is-active` command must report `inactive`, and the journal must contain
`database system is shut down`. Do not snapshot after a timeout, forced kill, or
ambiguous shutdown.

If the migration is aborted before deploying PostgreSQL 18, unmask the old unit
before attempting to restart it.

Identify and verify the exact datasets:

```sh
export DB_DATASET="$(findmnt -no SOURCE -T /mnt/SSD/apps/immich/db)"
export CACHE_DATASET="$(findmnt -no SOURCE -T /mnt/SSD/apps/immich/valkey)"
export MEDIA_DATASET="$(findmnt -no SOURCE -T /mnt/HDD/apps/immich/upload)"
export SNAPSHOT="pre-pg18-$MIGRATION_ID"

sudo zfs list "$DB_DATASET"
sudo zfs list "$CACHE_DATASET"
sudo zfs list "$MEDIA_DATASET"
```

Take both snapshots while Immich and PostgreSQL are stopped:

```sh
sudo zfs snapshot "$DB_DATASET@$SNAPSHOT"
if [ "$CACHE_DATASET" != "$DB_DATASET" ]; then
  sudo zfs snapshot "$CACHE_DATASET@$SNAPSHOT"
fi
sudo zfs snapshot "$MEDIA_DATASET@$SNAPSHOT"

sudo zfs list -t snapshot "$DB_DATASET@$SNAPSHOT"
sudo zfs list -t snapshot "$CACHE_DATASET@$SNAPSHOT"
sudo zfs list -t snapshot "$MEDIA_DATASET@$SNAPSHOT"
```

Keep PostgreSQL 14 stopped from this point.

## 9. Deploy and initialize PostgreSQL 18

Deploy the previously built configuration using the normal `serverone`
deployment procedure. Immich remains stopped because its unit is runtime-masked.

The new PostgreSQL service deliberately fails until its data directory has been
initialized. Stop its restart loop before initialization:

```sh
sudo systemctl stop nerdctl-postgresql.service
sudo systemctl reset-failed nerdctl-postgresql.service
```

Verify the old cluster remains PostgreSQL 14:

```sh
test "$(sudo cat /mnt/SSD/apps/immich/db/PG_VERSION)" = 14
```

Explicitly initialize the new data directory:

```sh
sudo systemctl start postgresql-init.service
sudo systemctl status postgresql-init.service
test "$(sudo cat /mnt/SSD/apps/postgresql/18/PG_VERSION)" = 18
```

Start and verify PostgreSQL 18:

```sh
sudo systemctl start nerdctl-postgresql.service
sudo systemctl status nerdctl-postgresql.service

sudo nerdctl exec -i postgresql \
  psql -X -h /tmp -U postgres -d postgres -c \
  "SELECT version(); SHOW data_checksums; SHOW shared_preload_libraries;"
```

Require PostgreSQL 18.6, enabled checksums, and `vchord.so` in
`shared_preload_libraries`.

The container's Unix socket is at `/tmp` (`unix_socket_directories` in
`postgresql.conf`), not `/run/postgresql`: every `psql`, `pg_dump`,
`pg_restore`, and `vacuumdb` invocation against this container must pass
`-h /tmp`.

## 10. Create the Immich role and database

Open an interactive local administrative session:

```sh
sudo nerdctl exec -it postgresql \
  psql -X -h /tmp -v ON_ERROR_STOP=1 -U postgres -d postgres
```

Create the role and securely set the password to the value stored in the
`immich/db-password` secret:

```sql
CREATE ROLE immich
  LOGIN
  NOSUPERUSER
  INHERIT
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION
  NOBYPASSRLS;

\password immich
```

Create and restrict the database:

```sql
CREATE DATABASE immich
  OWNER immich
  TEMPLATE template0
  ENCODING 'UTF8';

REVOKE ALL ON DATABASE immich FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE immich TO immich;

\connect immich

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO immich;
```

Create every extension recorded in the source inventory except `plpgsql`. For
the expected Immich database:

```sql
CREATE EXTENSION vchord CASCADE;
CREATE EXTENSION earthdistance CASCADE;
CREATE EXTENSION pg_trgm;
CREATE EXTENSION unaccent;
CREATE EXTENSION "uuid-ossp";

SELECT extname, extversion, pg_get_userbyid(extowner) AS owner
FROM pg_extension
ORDER BY extname;

\quit
```

The extensions must be owned by `postgres`. Expected target versions are cube
1.5, earthdistance 1.2, pg_trgm 1.6, unaccent 1.1, uuid-ossp 1.1, pgvector 0.8.7,
and VectorChord 1.1.1.

## 11. Filter extension entries and restore

Generate the restore list with PostgreSQL 18:

```sh
sudo nerdctl exec -i postgresql \
  pg_restore -h /tmp --list < "$DUMP" \
  > "$BACKUP_DIR/restore.pg18.list"
```

The extensions already exist and must remain owned by `postgres`. Disable only
extension and extension-comment entries:

```sh
LC_ALL=C sed '/ EXTENSION /s/^/;/' \
  "$BACKUP_DIR/restore.pg18.list" \
  > "$BACKUP_DIR/restore.pg18.no-extensions.list"

chmod 0644 "$BACKUP_DIR/restore.pg18.no-extensions.list"

diff -u \
  "$BACKUP_DIR/restore.pg18.list" \
  "$BACKUP_DIR/restore.pg18.no-extensions.list"
```

The diff must contain only the expected source extensions. Copy the small list
into the container and stream the archive into `pg_restore`:

```sh
sudo nerdctl cp \
  "$BACKUP_DIR/restore.pg18.no-extensions.list" \
  postgresql:/tmp/restore.list

sudo nerdctl exec -i postgresql \
  pg_restore -h /tmp \
  --username=postgres \
  --role=immich \
  --dbname=immich \
  --use-list=/tmp/restore.list \
  --single-transaction \
  --exit-on-error \
  --no-owner \
  --no-privileges \
  --no-tablespaces \
  < "$DUMP"
```

Do not start Immich unless the restore exits successfully.

## 12. Validate the restored database

Generate target state by repeating the command from section 6 with `postgresql`
as the container name and `-h /tmp` added to `psql`, and write the result to:

```text
$BACKUP_DIR/target-database-state.csv
```

The counts must match exactly:

```sh
diff -u \
  "$BACKUP_DIR/source-database-state.csv" \
  "$BACKUP_DIR/target-database-state.csv"
```

Verify the role:

```sh
sudo nerdctl exec -i postgresql \
  psql -X -h /tmp -U postgres -d postgres -c \
  "SELECT rolname, rolsuper, rolinherit, rolcreatedb, rolcreaterole,
          rolreplication, rolbypassrls, rolcanlogin
   FROM pg_roles
   WHERE rolname = 'immich';"
```

Only `rolcanlogin` and `rolinherit` should be enabled.

Check indexes, constraints, and ownership:

```sh
sudo nerdctl exec -i postgresql \
  psql -X -h /tmp -v ON_ERROR_STOP=1 -U postgres -d immich <<'SQL'
SELECT n.nspname, c.relname
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE NOT i.indisvalid OR NOT i.indisready;

SELECT conname, conrelid::regclass
FROM pg_constraint
WHERE NOT convalidated;

SELECT n.nspname, c.relname, c.relkind,
       pg_get_userbyid(c.relowner) AS owner
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg_%'
  AND pg_get_userbyid(c.relowner) <> 'immich'
  AND NOT EXISTS (
    SELECT 1
    FROM pg_depend d
    WHERE d.objid = c.oid
      AND d.deptype = 'e'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM pg_depend d
    JOIN pg_type t ON d.classid = 'pg_type'::regclass AND d.objid = t.oid
    WHERE t.typrelid = c.oid
      AND d.deptype = 'e'
  )
ORDER BY n.nspname, c.relname;
SQL
```

All three queries must return zero rows. The third excludes `pg_toast`
relations and extension-owned composite types (for example VectorChord's
`sphere_*` types, whose extension membership is recorded through
`pg_type` rather than `pg_class`); those are system objects correctly
owned by `postgres`. Regenerate planner statistics:

```sh
sudo nerdctl exec postgresql \
  vacuumdb -h /tmp --username=postgres --dbname=immich --analyze-in-stages
```

The restore creates the indexes using the new extension versions, so an
additional VectorChord reindex is not required.

## 13. Start and validate Immich

Start Immich and follow its logs:

```sh
sudo systemctl unmask --runtime nerdctl-immich-redis.service
sudo systemctl start nerdctl-immich-redis.service
sudo systemctl unmask --runtime nerdctl-immich-server.service
sudo systemctl start nerdctl-immich-server.service
sudo journalctl -u nerdctl-immich-server.service -f
```

Confirm its sessions use the new role:

```sh
sudo nerdctl exec postgresql \
  psql -X -h /tmp -U postgres -d postgres -c \
  "SELECT usename, datname, application_name, client_addr, state
   FROM pg_stat_activity
   WHERE datname = 'immich'
   ORDER BY usename, application_name;"
```

Validate login, existing asset reads, an original photo and video, metadata
search, smart search, face search, a disposable upload, thumbnail generation,
and background jobs. Review both services for permission and extension errors.

Keep the PostgreSQL 14 cluster, dump, and snapshots until manual cleanup.

## Manual backups

This deployment uses manual logical backups. Create one before every Immich,
PostgreSQL, pgvector, or VectorChord upgrade:

```sh
backup_id="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/mnt/HDD/apps/postgresql/migrations/$backup_id"
backup="$backup_dir/immich.dump"
sudo install -d -m 0700 -o "$(id -u)" -g "$(id -g)" "$backup_dir"
umask 077
sudo nerdctl exec postgresql \
  pg_dump -h /tmp \
  --username=postgres \
  --role=immich \
  --dbname=immich \
  --format=custom \
  --no-owner \
  --no-privileges \
  > "$backup"
sha256sum "$backup" > "$backup.sha256"
```

## Extension upgrades

The pinned package assertions force extension upgrades to be deliberate. Before
changing either extension version, stop Immich, create and inspect a logical
dump, and take a snapshot. Deploy the new binaries while Immich remains stopped,
then update the extension SQL as `postgres`:

```sh
sudo nerdctl exec -i postgresql \
  psql -X -h /tmp -v ON_ERROR_STOP=1 -U postgres -d immich <<'SQL'
ALTER EXTENSION vector UPDATE;
ALTER EXTENSION vchord UPDATE;
REINDEX INDEX face_index;
REINDEX INDEX clip_index;
SQL
```

Review the pgvector, VectorChord, and Immich release-specific instructions before
running these commands. Validate extension versions and both indexes before
starting Immich.

## Rollback

The old cluster is the primary database rollback. If Immich has not been started
against PostgreSQL 18, the media tree is still unchanged and no media restore is
required. Once Immich has accepted any writes, the media tree must also be
returned to its cutover snapshot before reconnecting the old database.

Keep Immich stopped throughout rollback:

```sh
sudo systemctl mask --runtime nerdctl-immich-server.service
sudo systemctl stop nerdctl-immich-server.service
sudo systemctl mask --runtime nerdctl-immich-redis.service
sudo systemctl stop nerdctl-immich-redis.service
sudo systemctl is-active nerdctl-immich-redis.service
sudo systemctl stop nerdctl-postgresql.service
```

If Immich was started against PostgreSQL 18, first preserve the failed state and
restore only Immich's upload tree. This does not roll back unrelated applications
that share the same ZFS dataset:

```sh
export MIGRATION_ID="<the original migration ID>"
export SNAPSHOT="pre-pg18-$MIGRATION_ID"
export CACHE_PATH="/mnt/SSD/apps/immich/valkey"
export MEDIA_PATH="/mnt/HDD/apps/immich/upload"
export CACHE_DATASET="$(findmnt -no SOURCE -T "$CACHE_PATH")"
export MEDIA_DATASET="$(findmnt -no SOURCE -T "$MEDIA_PATH")"
export CACHE_MOUNTPOINT="$(findmnt -no TARGET -T "$CACHE_PATH")"
export MEDIA_MOUNTPOINT="$(findmnt -no TARGET -T "$MEDIA_PATH")"
export CACHE_RELATIVE="${CACHE_PATH#"$CACHE_MOUNTPOINT"/}"
export MEDIA_RELATIVE="${MEDIA_PATH#"$MEDIA_MOUNTPOINT"/}"
export SNAPSHOT_CACHE="$CACHE_MOUNTPOINT/.zfs/snapshot/$SNAPSHOT/$CACHE_RELATIVE"
export SNAPSHOT_MEDIA="$MEDIA_MOUNTPOINT/.zfs/snapshot/$SNAPSHOT/$MEDIA_RELATIVE"
export FAILED_SNAPSHOT="failed-pg18-$MIGRATION_ID-$(date -u +%Y%m%dT%H%M%SZ)"

sudo test -d "$SNAPSHOT_CACHE"
sudo test -d "$SNAPSHOT_MEDIA"
sudo zfs snapshot "$CACHE_DATASET@$FAILED_SNAPSHOT"
sudo zfs snapshot "$MEDIA_DATASET@$FAILED_SNAPSHOT"
sudo rsync --archive --hard-links --acls --xattrs --delete \
  "$SNAPSHOT_CACHE/" \
  "$CACHE_PATH/"
sudo rsync --archive --hard-links --acls --xattrs --delete \
  "$SNAPSHOT_MEDIA/" \
  "$MEDIA_PATH/"
```

This intentionally discards post-cutover queue and media changes from the active
trees so they exactly match PostgreSQL 14. The `failed-pg18-*` snapshots preserve
those changes for investigation or manual recovery.

Switch to the previous NixOS generation and old secrets revision:

```sh
sudo nixos-rebuild switch --rollback
```

Start and verify PostgreSQL 14 before starting Immich:

```sh
sudo systemctl unmask --runtime nerdctl-immich-database.service
sudo systemctl start nerdctl-immich-database.service
sudo nerdctl exec immich-database \
  psql -X -U postgres -d immich -c \
  "SELECT version(), current_database();"

sudo systemctl unmask --runtime nerdctl-immich-server.service
sudo systemctl unmask --runtime nerdctl-immich-redis.service
sudo systemctl start nerdctl-immich-redis.service
sudo systemctl start nerdctl-immich-server.service
```

Confirm Immich health before doing anything further with the PostgreSQL 18
directory.

## Cleanup

Cleanup is always manual. Before deleting PostgreSQL 14, run PostgreSQL 18 for
an extended period, create and test another logical backup, take a fresh
snapshot, and confirm rollback is no longer required.

The protected migration artifacts are:

```text
/mnt/SSD/apps/immich/db
/mnt/SSD/apps/postgresql/18
/mnt/HDD/apps/postgresql/migrations/<migration ID>
<database dataset>@pre-pg18-<migration ID>
<cache dataset>@pre-pg18-<migration ID>
<media dataset>@pre-pg18-<migration ID>
<cache dataset>@failed-pg18-<migration ID>-<rollback timestamp>
<media dataset>@failed-pg18-<migration ID>-<rollback timestamp>
```
