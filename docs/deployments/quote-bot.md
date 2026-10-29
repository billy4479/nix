# quote-bot self-hosting (off vercel + turso)

This runbook moves quote-bot from the vercel + turso hosting to a container
on serverone. The bot itself is unchanged: same webhook, same commands, same
chats. What changes is where it runs and where the archive lives.

## Target state

- Container `quote-bot` at `10.0.1.26` (UID/GID `5026:5000`), image built
  from the `billy4479/quote-bot` flake.
- Archive as a SQLite file at `/mnt/SSD/apps/quote-bot/quotebot.db`
  (created on first use, WAL mode).
- Webhook served at `https://quote-bot.polpetta.online/api/webhook`
  (public tier, protected by the webhook secret).
- No vercel project and no turso database anymore.

## 1. Push the repo and update the lock

The flake input reads `billy4479/quote-bot` (master) over ssh, so the
self-hosting commits must be on GitHub. Then refresh the lock:

```sh
nix flake lock --update-input quote-bot
```

## 2. Add the secrets

In the secrets repository (serverone.yaml), add four hierarchical keys with
the values of the old vercel `.env`:

- `quote-bot/telegram-token`
- `quote-bot/webhook-secret`
- `quote-bot/chat-polpetta`
- `quote-bot/chat-quotebook`

The service renders them into the dotenv the container reads (same style as
grafana), so the repo never carries the values. Update the flake lock to
the new secrets revision and do not deploy yet.

## 3. Migrate the archive

The data moves from turso into the SQLite file the container will use. From
a clone of the quote-bot repo (this runs the old libsql driver to read
turso and the new one to write the file):

```sh
cd quote-bot
nix develop
export DATABASE_NAME=<turso db name>       # e.g. quotebook-bot-billy4479
export DATABASE_TOKEN=<turso auth token>
export DATABASE_PATH=/mnt/SSD/apps/quote-bot/quotebot.db
go run ./cmd/migrate
```

The tool recreates the table from scratch and refuses to write when the
row counts disagree, so it is safe to re-run. Run it once now to have a
tested database, and once more after the last vercel deploy, right before
the webhook switch, so quotes posted in between are kept.

## 4. Build and deploy

Validate the system still builds, then deploy serverone:

```sh
nix build .#nixosConfigurations.serverone.config.system.build.toplevel
```

The volume directory is created by the containers module on first start.

## 5. Switch the webhook

Point Telegram at the new URL (from a clone of the quote-bot repo, with
`TELEGRAM_BOT_TOKEN`, `TELEGRAM_WEBHOOK_URL=https://quote-bot.polpetta.online`
and `TELEGRAM_WEBHOOK_SECRET` in the environment or `.env`):

```sh
./setwebhook.sh
```

The secret must match `quote-bot/webhook-secret`, or Telegram's posts are
rejected with 401.

## 6. Verify

- `curl https://quote-bot.polpetta.online/api/healthz` returns `ok`.
- `/stats` in the admin chat reports the expected totals.
- Post a photo in the quotebook chat and check the reply has a sane id,
  then fetch it back with `/getmessagewithid <id>`.

## 7. Decommission

Once verified:

- delete the vercel project (`vercel` dashboard, project
  `prj_caGsEfx0dtDEwGn2kBAJKB68CaaX`);
- keep the turso database around for a while as a backup, then delete it.

## Rollback

`setwebhook.sh` against the old vercel URL points Telegram back at vercel
within seconds; quotes posted in the meantime live only in the SQLite file
and would need `cmd/migrate` in reverse (out of scope: re-running the
forward migration after a short rollback is simpler).
