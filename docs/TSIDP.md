# tsidp (OIDC identity provider)

This document describes how `tsidp` is deployed on `serverone` and how it is
wired to the existing headscale, nginx and bind9 stack.

## What it is

`tsidp` is Tailscale's OIDC identity provider: it authenticates users by
checking **which tailnet node their browser connects from** (WhoIs), so there
are no passwords to manage for self-hosted relying parties (RPs) like Grafana.
It is only useful for services inside the tailnet — it cannot be used as the
login provider for new headscale enrollments, and funnel/SaaS scenarios are
impossible by design.

## Architecture

The container (id 25, IP `10.0.1.25`) runs a **patched** `tsidp` from
`myPackages` (the `tsidp` branch of `nix-packages`). The patch adds three
flags, each needed because tsidp assumes it sits directly on the tailnet with
Tailscale-provisioned TLS, which headscale cannot do:

- `-listen 0.0.0.0:8080`: plain HTTP listener. headscale cannot provision the
  tailnet TLS certificates tsidp normally uses, so TLS is terminated by nginx
  instead.
- `-trusted-proxy 10.0.1.6`: honor `X-Real-IP` for WhoIs lookups only when the
  TCP peer is the nginx container. Identity arrives via the reverse proxy.
- `-server-url https://idp.internal.polpetta.online`: the OIDC issuer must be a
  name resolvable through bind9/nginx, not the node's MagicDNS name.

Traffic path:

```text
browser -> bind9 (wg/lan view wildcard) -> nginx 10.0.1.6:443 (TLS, tailnet ACL)
        -> tsidp 10.0.1.25:8080
```

WhoIs depends on seeing the browser's real tailnet IP, so serverone runs with
`--snat-subnet-routes=false`: without it, tailnet clients traversing the
advertised `10.0.1.0/24` route arrive at nginx source-NAT'ed and every WhoIs
lookup fails with `peer not found`.

tsidp itself joins the tailnet as node `idp` (tagged `tag:idp`) via
`TS_CONTROL_URL` through nginx -> headscale. Its tailnet IP is never used for
traffic; only the container IP behind nginx is. The `tag:idp` tag comes from
the preauth key (see checklist): headscale >= 0.29 rejects any registration
that combines a preauth key with client-advertised tags
(`-advertise-tags`), so tsidp must not be given that flag.

## Headscale policy

`policy.mode` is `database`, so policy is applied through the headplane UI. Add:

- a `tagOwners` entry:
  ```json
  { "tag:idp": ["jack@"] }
  ```
- a grants entry (the `extraClaims` are what make the user mapping work —
  see the Grafana recipe below):
  ```jsonc
  {
    "src": ["jack@"],
    "dst": ["tag:idp"],
    "app": {
      "tailscale.com/cap/tsidp": [
        {
          "allow_admin_ui": true,
          "allow_dcr": true,
          "includeInUserInfo": true,
          "extraClaims": { "grafana_role": "Admin" }
        }
      ]
    }
  }
  ```

Adjust `jack@` to the actual headscale LoginName. The grant above doubles
as the user-mapping source for relying parties: its `extraClaims` (here
`grafana_role`) are embedded into tokens tsidp issues to that user, and
`includeInUserInfo` mirrors them into `/userinfo`. Per-user role
assignment is therefore done by adding per-user grants with different
`extraClaims` — RPs should restrict access by requiring a claim rather
than trusting any tailnet identity (see Grafana below).

## Setup checklist

1. Add the sops keys (see below): `tsidp/authkey` (the raw preauth key; a
   template renders it into `TS_AUTHKEY=...` for the container),
   `grafana/oauth-client-id`, `grafana/oauth-client-secret`.

   The preauth key must be created **with the tag baked in** (`--tags`); a
   tagged key also disables node key expiry, which is what we want for a
   long-lived idp node:
   ```sh
   sudo exec-in-container headscale headscale preauthkeys create \
     --user 1 --reusable --expiration 90d --tags tag:idp
   ```
2. Apply the headscale policy above in headplane.
3. Deploy `serverone`.
4. Verify the node `idp` appears in headscale, tagged `tag:idp`.
5. Open `https://idp.internal.polpetta.online`, register a client for Grafana
   with redirect URI
   `https://grafana.internal.polpetta.online/login/generic_oauth`, put the
   client id/secret into the sops secrets and redeploy.
6. Login test on Grafana.

## Relying party recipe

Discovery is not usable by all RPs (Grafana needs explicit URLs), so:

- Issuer: `https://idp.internal.polpetta.online`
- Authorize: `/authorize`, Token: `/token`, Userinfo: `/userinfo`
- Scopes: `openid profile email`
- PKCE: supported

### Grafana (as deployed)

```ini
GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP = "true"
GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH = "grafana_role"
GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_STRICT = "true"
GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH = "username"
```

Sign-up is safe because tsidp only authenticates tailnet members, and
`role_attribute_strict` rejects any login whose grant carries no
`grafana_role` claim — so only users with a per-user grant get accounts
(currently jack, as Admin). The local `admin` account remains as
password fallback.

### Headplane (as deployed)

headplane (the `oidc:` block in
`services/services/headplane/headplane.yaml`) authenticates against tsidp:

- Issuer: `https://idp.internal.polpetta.online` (endpoints are
  auto-discovered; PKCE S256 is enabled)
- Scopes: `openid email profile` (all tsidp supports)

Client registration in the tsidp admin UI
(`https://idp.internal.polpetta.online`):

- Name: `headplane`
- Redirect URI (must match exactly — note the `/admin` prefix and **no
  explicit `:443`**, which headplane drops when building the URI from
  `server.base_url`):
  `https://headplane.internal.polpetta.online/admin/oidc/callback`
- Auth method: either works. headplane tries `client_secret_post` first
  and falls back to `client_secret_basic`; tsidp supports both, so
  `oidc.token_endpoint_auth_method` is left unset.

Add to the `headplane-env` sops file (plain `KEY=value` lines; headplane
merges `HEADPLANE_*__*` env overrides into its config automatically since
0.7, no `HEADPLANE_LOAD_ENV_OVERRIDES` flag needed):

- `HEADPLANE_OIDC__CLIENT_ID` / `HEADPLANE_OIDC__CLIENT_SECRET`: the
  registered client credentials
- `HEADPLANE_HEADSCALE__API_KEY`: a server-side headscale API key,
  created with `headscale apikeys create --expiration 999d`; headplane
  disables OIDC entirely without one (this is `headscale.api_key`)

First login: the first OIDC user becomes headplane **Owner** and is
asked to link their headscale user during onboarding (link it to
`jack@`); any later user lands as a no-access **Member** until granted
access in the headplane UI.

**Access model (user decision — containment):** only jack may *use*
headplane, but anyone on the tailnet may *authenticate*: headplane 0.7.1
has no allow-list, and the first-login Owner bootstrap is unconditional
(verified in source — it overrides even a role claim). Therefore
**jack must complete the first SSO immediately after deploy**, before
anyone else touches the URL; afterwards every other user is a permanent
zero-capability Member (an inert row in the user list). Hard-blocking
authentication at the IdP was evaluated (a `restrict_clients` tsidp
grant enforced at /authorize) and deliberately skipped as overkill.

API-key login stays enabled (`oidc.disable_api_key_login` is unset), so
the traditional headscale API-key login remains as break-glass fallback.

### Immich (as deployed)

Immich 3.2.2 (the `pkgs.immich` in this flake's pin, running as the
`immich-server` container) keeps its OAuth settings **in its own
database**, not in nix config and not in env vars —
`services/services/immich-server.nix` has no declarable OAuth surface.
Everything below happens in Immich's admin UI (persisted to the
`system_config` table) or in the `immich-database` container.

Client registration in the tsidp admin UI
(`https://idp.internal.polpetta.online`):

- Name: `immich`
- Redirect URIs (tsidp matches **exactly**, one per line in the form;
  only the first is strictly required — save the generated client id +
  secret, tsidp shows them once):
  - `https://immich.internal.polpetta.online/auth/login` — web login
    flow (Immich sends the login-page URL minus query string as
    `redirect_uri`)
  - `https://immich.internal.polpetta.online/user-settings` — needed
    only for the self-service **Link to OAuth** button (user settings)
  - `app.immich:///oauth-callback` — mobile app only (not used in this
    tailnet-only deployment)

Identity mapping, and why Immich's email matching cannot be used:
tsidp's `sub` is the headscale **numeric user id as a string** (jack
`1`, alice `2`, bob `3`, carol `4`), while `email` is the headscale
LoginName passed through (`jack@`) — not a routable address. Immich
resolves an OAuth login by `user.oauthId` **first**, then by email,
then auto-registers. Without a pre-set `oauthId`, the first OIDC login
of alice/bob/jack would auto-register a **duplicate** account with
email `alice@` etc. Bind existing accounts *before* enabling OAuth.

Admin UI (Administration → Settings → Authentication → OAuth), values
verified against the 3.2.2 source; defaults are fine unless noted:

| Field | Value |
| --- | --- |
| Login with OAuth | on |
| issuer_url | `https://idp.internal.polpetta.online` |
| client_id / client_secret | from the tsidp registration |
| token_endpoint_auth_method | `client_secret_post` (default; tsidp supports it) |
| scope | `openid email profile` (default; all tsidp supports) |
| id_token_signed_response_alg | `RS256` (default; tsidp signs RS256 only, so no algorithm mismatch) |
| userinfo_signed_response_alg | `none` (default; Immich reads the ID token because it carries `email`) |
| prompt, end_session_endpoint, account management URL | empty |
| Storage Label Claim | `preferred_username` (default; auto-registered users get a library dir named after their headscale username) |
| Role Claim / Storage Quota Claim | `immich_role` / `immich_quota` (defaults; absent in tsidp, so admin status and quotas are never touched) |
| Default Storage Quota | empty (no quota) |
| Auto Register | **on** (required for carol, who has no Immich account) |
| Auto Launch | off (keeps the password form visible) |
| Mobile Redirect URI Override | off (tsidp accepts the native `app.immich:///oauth-callback`) |
| Password → Enable password login | **on** — stays as break-glass fallback |

Profile pictures: Immich pulls the `picture` claim when a user has no
profile picture; headscale profiles are empty, so nothing changes.

Binding the existing users — no SQL is required. Immich resolves an
OAuth login by `oauthId` → **email match** → auto-register, and after
the headscale users got real email addresses the token emails match two
of the three Immich accounts:

- **alice, bob**: nothing to do. Their Immich emails equal the token
  emails (`alice@example.com`, `bob@example.com`), so the
  first OAuth login matches by email and links the existing account.
- **jack**: the token says `jack@example.com` but the Immich
  account has `jack.doe@example.com` — email matching misses, and
  auto-register would create a duplicate. Pick one, both are UI-only:
  1. **Link to OAuth** (recommended): while password-logged-in, User
     Settings → OAuth → *Link to OAuth*. Stores `sub` (`userid:1`) on
     the account; requires the `/user-settings` redirect URI (already
     in the registration list).
  2. As admin, change the Immich account's email to
     `jack@example.com`; the next OAuth login matches by email.
     Do this if you prefer the headscale email for Immich mail.

Do the binding **before** anyone's first OAuth login (auto-register is
on and would mint duplicates otherwise).

Scripted alternative (only if you ever need to rebind without logging
in as the user): SQL in the `immich-database` container (table
`"user"`, column `"oauthId"`; Immich reads it on each login, no restart
needed). On serverone, **backup first**, then update:

```sh
ssh serverone
# backup the user table (redirect happens host-side)
sudo exec-in-container immich-database pg_dump -U postgres -d immich \
  -t '"user"' --data-only > ~/immich-user-backup.sql

# bind: sub (userid:<n>) -> existing account
sudo exec-in-container immich-database psql -U postgres -d immich -c \
  "UPDATE \"user\" SET \"oauthId\" = 'userid:1' WHERE email = 'jack.doe@example.com';"
sudo exec-in-container immich-database psql -U postgres -d immich -c \
  "UPDATE \"user\" SET \"oauthId\" = 'userid:2' WHERE email = 'alice@example.com';"
sudo exec-in-container immich-database psql -U postgres -d immich -c \
  "UPDATE \"user\" SET \"oauthId\" = 'userid:3' WHERE email = 'bob@example.com';"

# verify: one row per sub
sudo exec-in-container immich-database psql -U postgres -d immich -c \
  "SELECT \"oauthId\", email, name, \"isAdmin\" FROM \"user\" ORDER BY \"oauthId\";"
```

Rollback is `UPDATE "user" SET "oauthId" = '';` scoped by email, or
restore the dump. Each sub must end up on exactly one user (there
is no uniqueness constraint on `oauthId`; on a collision the first
match wins silently). Note the admin API itself cannot set `oauthId`
in 3.2.2 (`PATCH /admin/users/{id}` has no such field); an Immich API
key is only useful for *verifying* (below).

Verification after enabling OAuth:

- With an admin API key (Account Settings → API Keys → *New API key*):
  ```sh
  curl -sH 'x-api-key: <key>' \
    https://immich.internal.polpetta.online/api/admin/users \
    | jq -r '.[] | [.name, .email, .oauthId] | @tsv'
  ```
  Jack/Alice/Bob must show oauthId `1`/`2`/`3`, not new users.
- Log in through the *Login with OAuth* button: Jack must land in his
  existing admin account (same assets and API keys, no second "jack"
  in the user list); carol is auto-registered on first login with
  email `carol@` — Immich accepts non-routable emails on
  auto-register (format validation only exists on the signup/admin
  create forms).
- Password login must keep working for all three existing users.

### Jellyfin (as deployed)

Jellyfin 12.1 (the `pkgs.jellyfin` in this flake's pin, container id 10) gets
the SSO plugin (**SSO-Auth** by 9p4, release `4.0.0.4`) **declaratively**:
`services/services/jellyfin.nix` builds the release zip into a nix-store
layout of `plugins/SSO-Auth/4.0.0.4/{SSO-Auth,Duende.IdentityModel,Duende.IdentityModel.OidcClient}.dll`
and read-only bind-mounts it onto `/config/plugins/SSO-Auth` (a nested ro
bind inside the rw `/config` volume). Jellyfin 12 auto-loads manifest-free
plugin folders (it scans `plugins/*/` recursively for `*.dll` and synthesizes
an `Active` manifest), so nothing has to be installed or updated through the
dashboard — bump the version in `jellyfin.nix` instead. The plugin's provider
configuration (which contains the client secret) lives in Jellyfin's own
config volume (`/config/plugins/configurations/SSO-Auth.xml`) and is done in
the admin UI, below.

Client registration in the tsidp admin UI
(`https://idp.internal.polpetta.online`):

- Name: `jellyfin`
- Redirect URI (must match exactly — one line, no trailing slash; the plugin
  builds it from the request's scheme/host behind nginx):
  `https://jellyfin.internal.polpetta.online/sso/OID/r/tsidp`
- Auth method: the plugin's OIDC client sends the secret as a **token-endpoint
  POST body parameter** (`client_secret_post`, the OidcClient default) —
  supported by tsidp.
- PKCE: the plugin always uses S256, tsidp supports it.

Login flow (all routes behind nginx, tailnet ACL): the web UI start URL is
`https://jellyfin.internal.polpetta.online/sso/OID/start/tsidp`, the IdP
bounces back to the redirect URI above, and the plugin's page completes the
login client-side (browser or any client with Quick Connect support).

Admin UI — Dashboard → Plugins → **SSO Authentication** → OpenID tab, add a
provider. Every field, exact values (defaults are fine unless noted):

| Field | Value |
| --- | --- |
| Name of OpenID Provider | `tsidp` (this is the `{provider}` in the redirect URI above — they must agree) |
| OpenID Endpoint | `https://idp.internal.polpetta.online/.well-known/openid-configuration` |
| OpenID Client ID / OpenID client secret | from the tsidp registration (secret shown once) |
| Enabled | **on** |
| Enable Authorization by Plugin | **off** — with this off the plugin never touches permissions: `jack` stays admin, existing users keep their access, and auto-created users keep Jellyfin's defaults (non-admin, all libraries, playback enabled). If it were on, every SSO login would demote users unless roles match, and tsidp has no roles to offer |
| Enable All Folders / Role-Based Folder Access | off (inert while RBAC is off) |
| Roles / AdminRoles / Role Claim | empty — empty `Roles` is what lets every tailnet identity pass the login gate |
| Request Additional Scopes | `email` (one line; the field is required — the plugin always sends `openid profile` itself, which covers every claim we use) |
| Set default username claim | `preferred_username` (leave empty — this is the default; it is the headscale username in the ID token) |
| Set default Provider / avatar url format | empty |
| Do Not Load Profile Information | off |
| Disable HTTPS Discovery / Disable Pushed Authorization / Do Not Validate Endpoints / Issuer Name (all "Insecure") | off |
| Scheme Override / Port Override | empty (nginx sends `Host` and `X-Forwarded-Proto`; if the IdP ever receives an `http://` redirect URI, set Scheme Override to `https`) |

Save the provider. The plugin does **not** add a button to the login page by
itself; to get one, paste the upstream snippet (Dashboard → General →
Branding → *Login disclaimer*):

```html
<form action="https://jellyfin.internal.polpetta.online/sso/OID/start/tsidp">
  <button class="raised block emby-button button-submit">Sign in with SSO</button>
</form>
```

Order-sensitive setup steps:

1. **Before any SSO login**: Dashboard → Users → rename `billy` → `jack`.
   The plugin matches identities to accounts **by username** (first by its
   stored canonical link, then by username, then creates a new user), so
   after the rename the headscale identity `jack` lands in the existing
   admin account. If the order is wrong, the first SSO login of `jack`
   silently creates a fresh **non-admin** `jack` and admin access stays
   stranded in `billy`.
2. Deploy `serverone`, confirm **SSO-Auth** shows as installed in
   Dashboard → Plugins (loaded from the read-only mount, no catalog entry).
3. Register the tsidp client (above), configure the provider in the plugin
   page (table above), Save.
4. Verify the mapping by logging in through SSO:
   - headscale `jack` and `carol` must land in the **existing** Jellyfin
     accounts (jack = admin; check Dashboard → Users for no duplicates);
   - `alice` and `bob` are auto-created on first login with standard
     permissions (non-admin, all libraries, playback on);
   - any other tailnet member can log in the same way.
5. Confirm the smart TV (`tv` user) still logs in from the LAN with its
   password / Quick Connect — **local and password auth stay fully enabled**;
   the plugin has no switch that disables them (each user keeps its own
   authentication provider; SSO users created by the plugin are pinned to it,
   everyone else is untouched). `tv` never uses SSO.

tsidp claim caveats that do **not** bite here (worth knowing):

- The `email` claim is the headscale LoginName (`jack@`), not a routable
  address — but this plugin never reads `email` (only the username claim and,
  if configured, the role claim and avatar format), so it is harmless.
- tsidp has no `oid` or `email_verified` claim and the plugin requires
  neither.
- If `preferred_username` were ever missing from the ID token (e.g. the
  registration lost the `profile` scope), the plugin silently falls back to
  `sub` and would create users named after headscale's numeric ids
  (`1`, `2`, …). If accounts with numeric names appear, that is why.
- Existing users can also self-link a different IdP identity at
  `/SSOViews/linking`; not needed for this setup, where usernames already
  match.

Break-glass: rename the provider or flip its `Enabled` checkbox off in the
plugin page (the config file `/config/plugins/configurations/SSO-Auth.xml`
is on the rw volume), and every user falls back to local login.

## Known limitations

- **STS disabled**: token exchange has no use here (no funnel/SaaS
  clients) and stays off. Node-identity attribution itself does work
  through the reverse proxy via `-trusted-proxy`; registered client
  secrets would work too, but there is no consumer for them.
- **No funnel**: tsidp is unreachable for public SaaS clients.
- **headscale's own `oidc:` block stays off**: `node.expiry: 0` means
  re-authentication never triggers, and new-device enrollment can never
  authenticate via tsidp (chicken-and-egg).
