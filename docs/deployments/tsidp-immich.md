# Immich as a tsidp relying party

## Keep in mind

- Immich keeps its OAuth settings **in its own database**, not in nix
  config and not in env vars (`services/services/immich-server.nix` has no
  declarable OAuth surface). Everything below happens in Immich's admin
  UI (persisted to the `system_config` table) or in the shared
  `postgresql` container.
- In tsidp, `sub` is `userid:<n>` (the headscale numeric user id) while
  `email` is the headscale Email field (see the invariant in TSIDP.md).
  Immich resolves an OAuth login by `user.oauthId` **first**, then by
  email, then auto-registers.
- Existing accounts are **already bound by `oauthId`** (jack `userid:1`,
  alice `userid:2`, bob `userid:3`), so the `email` claim plays no role in
  resolving their logins — and their stored (personal) Immich emails do
  **not** follow the headscale mail scheme, so headscale email changes
  cannot break their logins.
- Email matching only matters for an account whose `oauthId` is empty:
  bind such an account **before** its first OAuth login — Auto Register is
  on and would mint a duplicate instead of linking.

## tsidp client registration

Admin UI (`https://idp.internal.polpetta.online`):

- Name: `immich`
- Redirect URIs (tsidp matches **exactly**, one per line in the form;
  only the first is strictly required — save the generated client id +
  secret, tsidp shows them once):
  - `https://immich.internal.polpetta.online/auth/login` — web login flow
  - `https://immich.internal.polpetta.online/user-settings` — needed only
    for the self-service **Link to OAuth** button
  - `app.immich:///oauth-callback` — mobile app only (unused in this
    tailnet-only deployment)

## Admin UI

Administration → Settings → Authentication → OAuth. Defaults are fine
unless noted:

| Field | Value |
| --- | --- |
| Login with OAuth | on |
| issuer_url | `https://idp.internal.polpetta.online` |
| client_id / client_secret | from the tsidp registration |
| Auto Register | **on** (required for accounts without an Immich user) |
| Auto Launch | off (keeps the password form visible) |
| Password → Enable password login | **on** — stays as break-glass fallback |
| Mobile Redirect URI Override | off (tsidp accepts the native callback) |

Role/quota claims (`immich_role`, `immich_quota`) do not exist in tsidp,
so admin status and quotas are never touched. Profile pictures: Immich
pulls the `picture` claim, which headscale profiles never have.

## Rebinding an account without logging in as the user

SQL in the `postgresql` container (table `"user"`, column `"oauthId"`;
Immich reads it on each login, no restart needed). On serverone, **backup
first**, then update:

```sh
ssh serverone
# backup the user table (redirect happens host-side)
sudo exec-in-container postgresql pg_dump -h /tmp -U postgres -d immich \
  -t '"user"' --data-only > ~/immich-user-backup.sql

# bind: sub (userid:<n>) -> existing account, matched by the account's
# stored (personal) Immich email
sudo exec-in-container postgresql psql -h /tmp -U postgres -d immich -c \
  "UPDATE \"user\" SET \"oauthId\" = 'userid:1' WHERE email = '<jack-immich-email>';"

# verify: one row per sub
sudo exec-in-container postgresql psql -h /tmp -U postgres -d immich -c \
  "SELECT \"oauthId\", email, name, \"isAdmin\" FROM \"user\" ORDER BY \"oauthId\";"
```

Rollback is `UPDATE "user" SET "oauthId" = '';` scoped by email, or restore
the dump. Each sub must end up on exactly one user (there is no uniqueness
constraint on `oauthId`; on a collision the first match wins silently).
Note the admin API itself cannot set `oauthId` in Immich 3.2.2
(`PATCH /admin/users/{id}` has no such field); an Immich API key is only
useful for verifying:

```sh
curl -sH 'x-api-key: <key>' \
  https://immich.internal.polpetta.online/api/admin/users \
  | jq -r '.[] | [.name, .email, .oauthId] | @tsv'
```

## First-login expectations

- Existing, bound users land in their existing accounts (same assets and
  API keys, no second user in the list).
- Accounts with empty `oauthId` (e.g. carol, who has no Immich account)
  are auto-registered on first login; the headscale Email field is
  accepted as is (the strict email format validation only exists on the
  signup/admin create forms).
- Password login must keep working for pre-existing users.
