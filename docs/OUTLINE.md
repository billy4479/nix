# Outline

Outline (wiki / knowledge base, the `pkgs.outline` from this flake's
nixpkgs pin) on `serverone`, authenticated against tsidp.

## Layout

| Piece | Where |
| --- | --- |
| Outline container | id 24, `10.0.1.24`, image built from `pkgs.outline` |
| Web endpoint | `https://outline.internal.polpetta.online` (tailnet), nginx vhost generated from `polpetta.services.outline` |
| Redis/Valkey | `outline-valkey` container, id 133, `10.0.1.133:6379` (same shape as `immich-redis`) |
| PostgreSQL | shared `postgresql` container (`10.0.1.130`), role + database `outline` |
| Attachment storage | local file storage: `/mnt/SSD/apps/outline/data` → `/var/lib/outline/data` in the container |
| Service declaration | `services/services/outline.nix`, `services/services/outline-valkey.nix` |

Outline runs pending database migrations itself at boot
(`checkPendingMigrations` in `server/utils/startup.ts`); there is no
separate migrate step. The image entrypoint is
`bin/outline-server` from the nixpkgs package and the container
`workingDirectory` is `${pkgs.outline}/share/outline`, which Outline
needs to find its onboarding content (the NixOS module sets the same
directory).

## Secrets (sops)

`services/services/outline.nix` renders the `outline-env` template from
these keys (adding them restarts the container):

| Key | Value |
| --- | --- |
| `outline/secret-key` | `openssl rand -hex 32` |
| `outline/utils-secret` | `openssl rand -hex 32` |
| `outline/db-password` | `openssl rand -hex 32` (hex → safe to embed in the DATABASE_URL) |
| `outline/oauth-client-id` | from the tsidp client registration |
| `outline/oauth-client-secret` | from the tsidp client registration |

## PostgreSQL role and database

`pg_hba.conf` already carries the narrow rule
(`host outline outline 10.0.1.24/32 scram-sha-256`). The role and
database are created once, the same way as Immich's (see
POSTGRESQL_MIGRATION.md §10):

```sh
ssh serverone
sudo nerdctl exec -it postgresql psql -X -h /tmp -v ON_ERROR_STOP=1 -U postgres -d postgres
```

```sql
CREATE ROLE outline
  LOGIN
  NOSUPERUSER
  INHERIT
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION
  NOBYPASSRLS;

\password outline   -- paste the outline/db-password sops value

CREATE DATABASE outline
  OWNER outline
  TEMPLATE template0
  ENCODING 'UTF8';

REVOKE ALL ON DATABASE outline FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE outline TO outline;

\connect outline

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO outline;
\quit
```

## tsidp client registration

In the tsidp admin UI (`https://idp.internal.polpetta.online`):

- Name: `outline`
- Redirect URI (must match exactly):
  `https://outline.internal.polpetta.online/auth/oidc.callback`
- Auth method: Outline's passport-oauth2 client sends the secret in the
  token-endpoint POST body (`client_secret_post`) — supported by tsidp.

Save, then put the shown client id + secret into the sops keys above
(tsidp shows them once).

## Deploy checklist (order matters)

1. Add the five sops keys (above).
2. Register the `outline` client in the tsidp admin UI and fill the
   two oauth sops keys.
3. Create the PostgreSQL role + database (above).
4. Deploy `serverone`. The first boot creates the schema (migrations
   run automatically) and the first login creates the team.
5. **Jack logs in first**: the first user to sign in creates the team
   and becomes its admin — the headplane bootstrap rule applies here
   too. Anyone else on the tailnet who completes the login gets a
   regular member account (tsidp only authenticates tailnet members;
   the vhost is tailnet-only, so this is the same containment model as
   headplane — no app-level allow-list exists).
6. Verify: `https://outline.internal.polpetta.online` shows the login
   page with a "Continue with tsidp" button; a tailnet login lands in
   the account of the headscale user (username = short headscale name,
   see the claims section in TSIDP.md).

## Backups

- Database: logical dump like Immich's (POSTGRESQL_MIGRATION.md,
  "Manual backups"), with `--role=outline --dbname=outline`.
- Attachments: `/mnt/SSD/apps/outline/data` (plain file tree).
- Valkey (`/mnt/SSD/apps/outline/valkey`) holds only caches and job
  queues — not backed up; pending jobs are lost on restore.

## Notes and limitations

- **No SMTP configured**: notification and invite emails are disabled
  (users are provisioned by logging in, not by invitation, so nothing
  blocks on this). To enable later, add `SMTP_*` env entries to the
  container environment in `services/services/outline.nix`.
- **Local file storage**, not S3: `FILE_STORAGE=local` with the data
  volume above; Outline's public attachment URLs are served by Outline
  itself from `${URL}`.
- Outline's upload limit is `FILE_STORAGE_UPLOAD_MAX_SIZE` (250 MB) and
  the generated nginx vhost matches it via `client_max_body_size`.
- `ENABLE_UPDATES=false` — no update telemetry.
- Logout only ends the Outline session; tsidp re-authenticates a
  tailnet peer silently, so "logged out" lasts one click (same as ff).
