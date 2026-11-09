# Gmail review from T3 Code

The `t3code` image includes `mail-watch`, a Python standard-library helper.
Gmail access uses only `gmail.readonly`. Telegram alerts reuse the monitoring
bot/chat via separate sops secret aliases owned by UID 5021 and read-only mounts
at `/run/secrets/telegram-bot-token` and `/run/secrets/telegram-bot-chat-id`.
Existing host consumers keep their original secret ownership.

Deployment, Google account authorization and secret provisioning remain Billy's
responsibility. No task is enabled by this change. The desired schedule is
**09:00 and 18:00 Europe/Rome**, including daylight saving time.

## One-time authorization

1. In Google Cloud, create/select a project, enable the Gmail API, configure
   the OAuth consent screen and create an OAuth client of type **Desktop app**.
   Download its client JSON. Authorize only the intended Gmail account.
2. For unattended use, do not leave an external consent app in Testing:
   Gmail refresh tokens in that mode normally expire after seven days.
   Use the appropriate production/internal configuration for your account;
   Google may show an unverified-app warning or impose additional requirements.
3. Place the downloaded JSON privately inside the container, outside Git and
   `/agent-config`. In the container terminal, run:

   ```sh
   mail-watch authorize /path/to/client.json
   ```

   Open the printed Google URL on your own computer. After consenting, Google
   redirects to `http://127.0.0.1:8765/`. No callback server is started, so the
   page will fail to load. Copy the **whole URL from the address bar** and paste
   it into the waiting command. The helper validates OAuth state and uses PKCE.
   Do not paste the callback URL into an agent conversation or shared logs.
4. The refresh token/client credentials are written atomically with mode 0600
   to `~/.config/mail-watch/credentials.json`. Delete the downloaded client JSON
   when no longer needed. Do not commit or sync either credential file.

The token permits reading the entire mailbox. Label restriction is implemented
by the helper, not enforced by Google's OAuth scope. The agent runs under the
same UID and could read the credentials: this is not an OS security boundary.
Google account settings can revoke access.

## Label and editable prompt

Inside the container:

```sh
mkdir -p ~/.config/mail-watch
chmod 700 ~/.config/mail-watch
printf '%s\n' '{"label":"EXACT LABEL NAME"}' > ~/.config/mail-watch/config.json
cp /workspace/nix/services/mail-watch/prompt.md ~/.config/mail-watch/prompt.md
```

Edit the prompt's importance criteria and remove the TODO. Label names are
case-sensitive. There is deliberately no default label or importance policy.

The first review includes **all existing messages in that label**, not just
recent/unread messages. To avoid a large historical review, start with a new
label populated by a Gmail filter, or curate the label before enabling the task.
The helper retrieves up to 50 unreviewed messages per batch, with at most 30,000
plain-text body characters per message. HTML-only messages fall back to Gmail's
snippet; attachments are not downloaded. The prompt requires caution when
content is incomplete. No email content is written to helper state files.

Commands:

```sh
mail-watch pending                      # JSON, does not mark anything reviewed
mail-watch dismiss MESSAGE_ID           # record a reviewed, unimportant message
printf '%s\n' 'Alert text' | mail-watch notify MESSAGE_ID
```

`notify` sends plain text with link previews disabled. It accepts at most 4,000
characters. Message IDs are Gmail IDs from `pending`, not RFC Message-ID headers.
Reviewed IDs/statuses persist in `~/.local/state/mail-watch/reviewed.json`.
Do not delete that file unless you want to review old messages again. New replies
have new message IDs and will be reviewed if they match the label. Changes to
an already reviewed message or to your criteria do not trigger re-review.

State updates and sends are serialized, and failed sends do not mark IDs
reviewed. Telegram has no idempotency key: a crash after delivery but before the
state write, or an ambiguous network timeout, can still cause a duplicate alert.
Do not overlap scheduled runs or manually review in parallel.

## Enable the T3 task later

After deployment, authorization, label selection and prompt editing:

1. Run `mail-watch pending --limit 1` privately to verify Gmail access. Its
   output contains private email content; do not paste it into public logs.
2. Test delivery with a real pending message you want to be notified about.
   Successful delivery marks that ID reviewed.
3. Create two daily T3 scheduled tasks, at 09:00 and 18:00. Each task should
   read `~/.config/mail-watch/prompt.md` and follow it, so edits take effect
   without recreating schedules. Run them in the `t3code` environment, preferably
   in a dedicated mail-review thread rather than the Nix maintenance thread.
4. Confirm T3's actual scheduler timezone and next run times before enabling.
   If it uses host local time, ensure that is Europe/Rome; do not substitute
   fixed UTC times, which would drift with daylight saving time.

T3 must remain running for the jobs. Gmail/authentication failures are visible
in task results, but this integration cannot guarantee Telegram error alerts
when Telegram itself is unavailable. No systemd timer or unattended model
process is added by this module; scheduling belongs to T3.

Validation:

```sh
nix build .#checks.x86_64-linux.mail-watch
nix build .#nixosConfigurations.serverone.config.system.build.toplevel
```
