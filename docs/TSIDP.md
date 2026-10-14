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
`myPackages` (the `tsidp` branch of `nix-packages`). The patches add three
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

### Claims, as validated live (2026-10-14)

What tsidp actually puts in its tokens in this deployment:

- `sub` = `userid:<n>`, where `<n>` is the headscale numeric user id
  (jack `1`, alice `2`, bob `3`, carol `4`) — not a bare number.
- `email` = headscale's **Email field, verbatim** (a real, routable
  address such as `jack@example.com`): headscale sets the WhoIs
  LoginName to the user's Email when one exists, and tsidp passes it
  through (its `@github`/`@passkey` rewrite never fires here). Same
  value in the ID token and `/userinfo`.
- `username` (in `/userinfo`) and `preferred_username` (in the ID
  token, only granted with the `profile` scope) = the **short headscale
  username** (`jack`, `alice`, …), derived by the patched tsidp from the
  WhoIs **display name**: lowercased, with spaces replaced by `_` —
  `Jack` → `jack`, `Mary Jane` → `mary_jane`. (WhoIs carries no short
  username, only the email-shaped LoginName and the display name; the
  derivation is pure WhoIs — no headscale API, no API key, no network.)
  A display name that is empty **or is an email address** (headscale
  falls back to the user's email when no display name is set, and an
  email local part is not a username) yields no username: the claim
  falls back to the pre-`@` part of the LoginName, and stays omitted
  when the LoginName has no `@` — upstream's original semantics.
- `name` (in `/userinfo`) = headscale's DisplayName (e.g. `Jack`).
- `picture`, `key`, `nid`, `node`, `addresses`, `tailnet`, `uid`:
  tailscale claims, unchanged.

Live ID token payload (claims-audit client; `<…>` elided):

```json
{
  "iss": "https://idp.internal.polpetta.online",
  "sub": "userid:1",
  "aud": ["<client id>"],
  "exp": <unix>, "iat": <unix>, "nbf": <unix>,
  "jti": "<random hex>",
  "nonce": "<nonce>",
  "email": "jack@example.com",
  "preferred_username": "jack",
  "grafana_role": "Admin",
  "key": "<node public key>",
  "nid": 10,
  "node": "serverone.devices.polpetta.online.",
  "addresses": ["<tailnet ip>/32"],
  "tailnet": "devices.polpetta.online.",
  "uid": 1
}
```

Live `/userinfo` (same session):

```json
{
  "email": "jack@example.com",
  "grafana_role": "Admin",
  "name": "Jack",
  "sub": "userid:1",
  "username": "jack"
}
```

`grafana_role` comes from the headscale grant's `extraClaims` (see the
policy section). The short `preferred_username`/`username` values are
post-patch: before `displayname-username.patch` landed they were the
email local part (`jack`).

> **REQUIRED INVARIANT — display names are the username source.** Every
> headscale user must have a **display name whose normalized form
> (lowercase, spaces → `_`) equals their headscale username**: `Jack`
> for `jack`, `Mary Jane` for `mary_jane`. tsidp cannot verify this — a
> violation errors nowhere and silently degrades to the email-prefix
> derivation (`jack`), which then **mismatches downstream**:
> OpenCloud resolves accounts by the `username` claim, Jellyfin matches
> users by `preferred_username`, and ff compares it against
> `ALLOWED_USERNAME`. Set the display name **before** a user's first
> login, and keep the invariant across renames: rename the username and
> the display name together, or the account mapping moves.

Housekeeping: the throwaway DCR client `claims-audit-test` registered
in the admin UI during this validation can be deleted.

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

Identity mapping, and why binding beats email matching: tsidp's `sub`
is `userid:<n>` — the headscale numeric user id (jack `userid:1`,
alice `userid:2`, bob `userid:3`, carol `userid:4`; see the claims
section above) — while `email` is the headscale Email field verbatim
(a real address). Immich resolves an OAuth login by `user.oauthId`
**first**, then by email, then auto-registers. Bind existing accounts
*before* enabling OAuth so the explicit `oauthId` is authoritative and
no login can silently create a duplicate.

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

   # bind: sub (userid:<n>) -> existing account
   sudo exec-in-container immich-database psql -U postgres -d immich -c \
     "UPDATE \"user\" SET \"oauthId\" = 'userid:1' WHERE email = 'jack.doe@example.com';"
   sudo exec-in-container immich-database psql -U postgres -d immich -c \
     "UPDATE \"user\" SET \"oauthId\" = 'userid:2' WHERE email = 'alice@example.com';"
   sudo exec-in-container immich-database psql -U postgres -d immich -c \
     "UPDATE \"user\" SET \"oauthId\" = 'userid:3' WHERE email = 'bob@example.com';"

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
  Jack/Alice/Bob must show oauthId `userid:1`/`userid:2`/`userid:3`, not
  new users.
- Log in through the *Login with OAuth* button: Jack must land in his
  existing admin account (same assets and API keys, no second "jack"
  in the user list); carol is auto-registered on first login (email =
  the headscale Email field, which Immich's auto-register accepts as
  is — the strict email format validation only exists on the
  signup/admin create forms).
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
   stored canonical link, then by username, then creates a new user), and
   the username it sees is the ID token's `preferred_username` — the short
   headscale name `jack` (see the claims section). After the rename the
   headscale identity lands in the existing admin account. If the order is
   wrong, the first SSO login of `jack` silently creates a fresh
   **non-admin** `jack` and admin access stays stranded in `billy`.
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

- The `email` claim is the headscale Email field verbatim (a real,
  routable address) — this plugin never reads `email` (only the username
  claim and, if configured, the role claim and avatar format), so it
  does not matter either way.
- tsidp has no `oid` or `email_verified` claim and the plugin requires
  neither.
- If `preferred_username` were ever missing from the ID token (e.g. the
  registration lost the `profile` scope), the plugin silently falls back
  to `sub` and would create users named after headscale's user ids
  (`userid:1`, `userid:2`, …). If accounts with names like that appear,
  that is why.
- Existing users can also self-link a different IdP identity at
  `/SSOViews/linking`; not needed for this setup, where usernames already
  match.

Break-glass: rename the provider or flip its `Enabled` checkbox off in the
plugin page (the config file `/config/plugins/configurations/SSO-Auth.xml`
is on the rw volume), and every user falls back to local login.

### OpenCloud (as deployed)

OpenCloud 7.5.0 (`pkgs.opencloud`, container 14,
`https://opencloud.polpetta.online`) used the built-in IDP/IDM (embedded
LDAP under the config/data volumes). `services/services/opencloud.nix`
switches it to tsidp: the built-in `idp` service is excluded
(`OC_EXCLUDE_RUN_SERVICES=idp`), the **IDM keeps running** (it still holds
all accounts — auto-provisioning writes new users there), and proxy, web
and webfinger all read the issuer from `OC_OIDC_ISSUER`. Non-secret
settings are in the nix file; the tsidp client id is appended by the user
to the `opencloud-env` sops file (below). `OC_URL` stays public on
purpose (share links); every *authentication* path requires the tailnet,
because the only issuer is tsidp and local password auth is disabled
(`PROXY_ENABLE_BASIC_AUTH=false`).

#### The public-client gap: tsidp needs a small patch

OpenCloud's clients (web, desktop, Android, iOS) are **public OAuth
clients**: authorization code + PKCE, no client secret — the web frontend
has no client-secret setting at all (verified in `opencloud-eu/web`
v7.5.0: `packages/web-runtime/src/services/auth/userManager.ts`). tsidp
however requires client credentials at the token endpoint for every
client (`allowRelyingParty` in `server/token.go`), in the pinned build
(8fa860f) **and in current upstream main** (upstream decided this in
tailscale/tsidp#9). Without a patch, the login redirects work and the
token exchange always fails with `401 missing client credentials`.

Fix: patch tsidp in `nix-packages` (where `headscale-proxy.patch` already
lives) to accept secret-less clients — clients registered **without** a
secret — when the authorization request carried a PKCE S256 challenge. A
client that holds a registered secret is untouched: it keeps the upstream
path and must keep presenting its secret. The change landed as
`tsidp/public-clients.patch`, wired into `tsidp/default.nix` after
`headscale-proxy.patch`:

```diff
diff --git a/server/token.go b/server/token.go
--- a/server/token.go
+++ b/server/token.go
@@ -910,6 +910,27 @@ func (ar *AuthRequest) allowRelyingParty(r *http.Request) (int, error) {
 		clientSecret = r.FormValue("client_secret")
 	}
 
+	// Public clients send no client_secret (e.g. the OpenCloud web client is
+	// a public PKCE client registered without a secret). Authenticate them
+	// by client_id alone, but only when the registered client has no secret
+	// of its own: a client that holds a registered secret must keep
+	// presenting it and falls through to the credential check below. The
+	// public path also requires the authorization request to have carried a
+	// PKCE S256 challenge; the code_verifier is then enforced by
+	// handleAuthorizationCodeGrant before any token is issued.
+	if clientSecret == "" && ar.FunnelRP.Secret == "" {
+		if clientID == "" {
+			return http.StatusUnauthorized, fmt.Errorf("tsidp: missing client credentials")
+		}
+		if subtle.ConstantTimeCompare([]byte(clientID), []byte(ar.FunnelRP.ID)) != 1 {
+			return http.StatusBadRequest, fmt.Errorf("tsidp: client_id mismatch")
+		}
+		if ar.CodeChallenge == "" || ar.CodeChallengeMethod != "S256" {
+			return http.StatusUnauthorized, fmt.Errorf("tsidp: public clients must use PKCE S256")
+		}
+		return http.StatusOK, nil
+	}
+
 	if clientID == "" || clientSecret == "" {
 		return http.StatusUnauthorized, fmt.Errorf("tsidp: missing client credentials")
 	}
```

(The patch also adds `server/publicclients_test.go`, not shown: unit tests
for `allowRelyingParty`, full `/token` exchanges for secret-less clients —
success, missing/wrong `code_verifier`, no-PKCE rejection — and
refresh-token grants, which public clients must be able to run secret-less
after a PKCE login. Refinements over the earlier draft: constant-time
`client_id` comparison, distinct error codes — `400 client_id mismatch`,
`401 public clients must use PKCE S256` — while an empty `client_id` still
returns the original `401 missing client credentials`, and a tightening:
the public path only applies when the registered client has **no** secret
of its own — a client with a registered secret cannot drop it and gets the
original `401` when it sends none.) Then:
commit + push `nix-packages`, and in this flake run
`nix flake lock --update-input myPackages`. Consequence of the tightening:
the OpenCloud client must be registered **without** a secret. tsidp always
generates one at registration (admin UI and dynamic registration alike) —
so after registering, clear the `Secret` field by hand-editing
`oidc-funnel-clients.json` in tsidp's state dir
(`/mnt/SSD/apps/tsidp/lib` on serverone) **while tsidp is stopped** (it
rewrites the file from memory on changes). Nothing else consumes the
secret. PKCE remains mandatory:
the `code_verifier` check in `handleAuthorizationCodeGrant` is untouched.

#### Client registration via DCR (not the admin UI)

OpenCloud is **not** registered in the tsidp admin UI: every client the UI
creates gets a generated secret, and OpenCloud needs a secret-less public
client. Register it with the RFC 7591 dynamic registration endpoint, which
honours `token_endpoint_auth_method: "none"` (post-patch) and stores the
client with an empty secret.

- Name: `opencloud`
- Redirect URIs (tsidp matches **exactly**, one per line — the web
  frontend builds both from the router base, verified in the web source):
  - `https://opencloud.polpetta.online/oidc-callback.html`
  - `https://opencloud.polpetta.online/oidc-silent-redirect.html`
- Save: tsidp shows client id + secret **once**. Record the secret
  somewhere safe (unused by OpenCloud), then clear it from the registered
  client — the tightened patch requires a secret-less client (procedure
  above). Append the client id to the sops env file:

  ```sh
  # in /workspace/code/nix-secrets, append to the opencloud-env plaintext:
  OC_OIDC_CLIENT_ID=<client_id from the response>
  ```

  `OC_OIDC_CLIENT_ID` is read by the web service (config.json
  `openIdConnect.client_id`) and by webfinger (the `client_id` property
  web clients discover at `/.well-known/webfinger`). The registered client
  shows up in the tsidp admin UI list like any other client and can be
  deleted there.

Webfinger discovery is **mandatory** for the web UI to boot (it fails
closed with "OIDC configuration could not be loaded via webfinger"), and
it is served by OpenCloud itself from the same env — no extra setup.

#### Roster and data (recon 2026-10-14, read-only)

The IDM database (`/mnt/HDD/apps/opencloud/idm/idm.boltdb`) holds exactly
one human account — `jack` (displayName *redacted*, mail
`jack@example.com`) — plus internal sysusers (`reva`, `libregraph`,
`idp`). **alice, bob and carol have no OpenCloud accounts and no data.**
Storage has one personal space (`887686ba-95d9-4c88-b01d-4da9fb4f3579`,
~40G) and three project spaces. Auto-provisioned accounts get **fresh
random UUIDs** (the proxy's `CreateUserFromClaims` never sends an id; the
graph/LDAP backend generates one) — that is why fresh accounts can never
see the old account's data without a copy.

#### Decision point — the migration plan (user judgment)

Both plans use the **same nix config**; they differ only in what happens
to the existing `jack` account before/after the deploy. The nix config
maps tsidp's `username` claim to the LDAP `username`, so **a headscale
user whose short username (derived from the display name, see the
claims section) matches an existing LDAP username logs into that
existing account** (same UUID, data, shares, spaces, role) — for jack
that is exactly the case. alice/bob/carol have nothing to collide with and
auto-provision fresh either way.

- **Plan A — zero-copy (recommended):** do nothing to the old account.
  First tsidp login of headscale `jack` lands in the existing account:
  40G of data, all three project spaces, every share and public link
  keep working untouched. No copy window, no data ever at risk.
  Deviation from the original "fresh accounts" decision: only for jack,
  and it is invisible day-to-day (there is no password login left to
  distrust — the IdP is tsidp and basic auth is off).
- **Plan B — fresh account + copy (the original decision):** rename the
  old `jack` account **before** the deploy (otherwise his first tsidp
  login lands in the old account), let a fresh `jack` auto-provision,
  then copy the data over WebDAV with app tokens. Costs: ~40G copy,
  project spaces re-created by hand, shares/public links re-created by
  hand, old data kept as a frozen archive.

#### Before the deploy (both plans)

1. **Backups** (needs sudo):

   ```sh
   ssh serverone
   sudo cp -a /mnt/HDD/apps/opencloud/idm /mnt/HDD/apps/opencloud/idm.backup-$(date +%F)
   sudo cp -a /mnt/SSD/apps/opencloud/config /mnt/SSD/apps/opencloud/config.backup-$(date +%F)
   sudo du -ah /mnt/HDD/apps/opencloud/storage/users | sort -k2 > ~/opencloud-storage-listing-$(date +%F).txt
   ```

   The 40G of file data itself is not backed up: neither plan deletes or
   rewrites it (Plan A never touches it; Plan B copies and leaves the
   original in place as the archive).
2. **Mint app tokens that survive the IdP switch** — app tokens are
   validated by the auth-app service (IdP-independent), so they keep
   working after `idp` is gone (web UI: *Settings → App tokens*, or
   `POST /auth-app/tokens?expiry=8760h` while logged in; save the
   cleartext token):
   - one for the OpenCloud `admin` user (break-glass admin API access
     after the switch — the `admin` account itself becomes unloggable),
   - one for `jack` (only needed for Plan B's copy, cheap to have anyway).
3. Register the opencloud client via the DCR call (above) and append
   `OC_OIDC_CLIENT_ID` to the `opencloud-env` sops file. Confirm the
   tsidp patch is in the built tsidp (`nix flake lock --update-input
   myPackages` first).
4. **Plan B only:** rename the old `jack` account now (still on the old
   IdP), using the admin app token just minted — see the first step of
   "Plan B only — the copy" below; it must happen **before** the deploy,
   or jack's first tsidp login lands in the old account.

#### Deploy and verify

1. Deploy `serverone`. Watch the logs: `journalctl -u nerdctl-opencloud.service -f`
   — the `idp` service must not start; proxy/web/webfinger must come up.
2. From the tailnet, `curl -s https://opencloud.polpetta.online/.well-known/openid-configuration | jq .issuer`
   must return `https://idp.internal.polpetta.online` (the proxy rewrites
   the well-known to the issuer's document).
3. Web login as headscale `jack` (Plan A: must land in the *existing*
   account — files/spaces intact, no second jack in
   *Administration → Users*). alice/bob/carol log in once each: fresh
   accounts are created on the fly (role *user*, displayName from the
   userinfo `name` claim = headscale DisplayName, mail from the `email`
   claim = headscale Email).
4. Roles: auto-provisioned users get *user*. To make jack an OpenCloud
   admin, use the admin app token:

   ```sh
   ADMIN_USER=admin ADMIN_TOKEN=<admin app token>
   # find the new jack's id
   curl -su "$ADMIN_USER:$ADMIN_TOKEN" https://opencloud.polpetta.online/graph/v1.0/users | jq -r '.value[]|[.id,.onPremisesSamAccountName]|@tsv'
   # promote (the Admin role bundle id is a fixed default in OpenCloud)
   curl -su "$ADMIN_USER:$ADMIN_TOKEN" -X POST \
     https://opencloud.polpetta.online/graph/v1.0/users/<new-jack-id>/appRoleAssignments \
     -H 'Content-Type: application/json' \
     -d '{"appRoleId":"71881883-1768-46bd-a24d-a356a2afdf7f"}'
   ```

   (Plan A note: the existing jack already has his old roles.)
5. Outsiders must get nothing: from a non-tailnet vantage,
   `https://opencloud.polpetta.online` serves the login page but the only
   issuer link points into the tailnet, and `PROXY_ENABLE_BASIC_AUTH=false`
   leaves no password path. Public share links (anonymous, token+password
   via the proxy's public-share middleware) do **not** touch the IdP —
   they keep working, as long as the underlying resource/account stays
   (true in Plan A; in Plan B only for links on data that was not copied).

#### Plan B only — the copy

1. **Before** the deploy, rename the old account so tsidp's `jack` cannot
   resolve to it (with the admin app token):

   ```sh
   curl -su "$ADMIN_USER:$ADMIN_TOKEN" -X PATCH \
     https://opencloud.polpetta.online/graph/v1.0/users/<old-jack-id> \
     -H 'Content-Type: application/json' -d '{"onPremisesSamAccountName":"jack-migrated"}'
   ```

2. After the deploy: headscale `jack` logs in once (fresh account, fresh
   UUID), creates his own app token; then copy with rclone over WebDAV
   (app tokens = Basic auth, works with basic auth disabled):

   ```sh
   # old account (renamed pre-deploy) and new account, one remote each
   rclone config create oc-old webdav \
     --webdav-url https://opencloud.polpetta.online/remote.php/dav/files/jack-migrated \
     --webdav-user jack-migrated --webdav-pass "$(rclone obscure <old-jack-app-token>)"
   rclone config create oc-new webdav \
     --webdav-url https://opencloud.polpetta.online/remote.php/dav/files/jack \
     --webdav-user jack --webdav-pass "$(rclone obscure <new-jack-app-token>)"

   rclone copy oc-old: oc-new: -P --size-only   # ~40G, re-run safe
   ```
3. The three project spaces: re-create them in the web UI as the new
   admin/jack, then rclone the content the same way using each space's
   WebDAV URL (`/remote.php/dav/spaces/<space-id>`). Re-set quotas and
   descriptions via the graph API. Shares and public links must be
   re-created manually (they reference the old resource ids).
4. The old account stays frozen as the rollback/archive. Deleting it
   later (graph `DELETE /users/<id>`) does **not** purge its 40G of
   storage — space cleanup is a separate manual job; decide later.

#### Rollback

Redeploy the previous system closure (e.g. from the previous commit of
this flake): with the env vars gone the proxy falls back to the built-in
IdP defaults and `OC_EXCLUDE_RUN_SERVICES` unset restarts `idp`. This is
genuinely reversible: `opencloud init` is a no-op once `opencloud.yaml`
exists (verified in `opencloud/pkg/command/init.go` +
`opencloud/pkg/init/init.go` — it refuses to overwrite without
`--force-overwrite`, and the container cmd `opencloud init || true`
swallows that), so the generated config with all its secrets is never
regenerated. The IDM database is untouched by both plans (backups above
cover it anyway). Auto-provisioned accounts from the brief tsidp period
remain in the LDAP and are inert — delete them via graph if desired. App
tokens keep working on both sides of the rollback (they never touch the
IdP). After a Plan A rollback the built-in IdP login works exactly as
before (jack's old account/password state unchanged).

OpenCloud-specific caveats worth knowing:

- `PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD=none` is **required**: tsidp's
  access tokens are opaque random strings (`rands.HexString(32)`), not
  JWTs; the proxy default `jwt` would fail every request. Claims are read
  from `/userinfo`.
- tsidp's userinfo has `username`, **not** `preferred_username` — that is
  why `PROXY_USER_OIDC_CLAIM=username` here, while the official docs use
  `preferred_username` (Keycloak examples). Either way the value is the
  short headscale username (`jack`), derived from the headscale display
  name (see the claims section).
- Display names come from the userinfo `name` claim (= headscale's
  DisplayName, e.g. `Jack`; `PROXY_AUTOPROVISION_CLAIM_DISPLAYNAME=name`):
  the proxy re-applies `displayName`/`mail` from claims on every login
  (`UpdateUserIfNeeded`), so editing the display name in OpenCloud web is
  undone at the next login (jack's *redacted* becomes `Jack`,
  Plan A too). Refinement (optional): set proper display names on the
  headscale users and switch
  `PROXY_AUTOPROVISION_CLAIM_DISPLAYNAME` to `name` — **only safe if
  every headscale user has a non-empty DisplayName**, otherwise their
  login 500s (missing claim).
- headscale usernames are the join key: renaming a headscale user later
  mints a *new* OpenCloud account on next login (the old one stays).
  Renaming an OpenCloud account (graph) has the mirror effect. A rename
  must keep the display-name invariant (display name = username,
  normalized — see the claims section) or the next login's `username`
  claim no longer matches.
- The `email` claim is the headscale Email field verbatim (a real
  address for users that have one); auto-provisioning accepts whatever
  it carries (email is optional in the provisioning code —
  if provisioning ever fails on mail, point
  `PROXY_AUTOPROVISION_CLAIM_EMAIL` at a nonexistent claim name to drop
  it).
- Desktop/Android/iOS clients: OpenCloud expects predefined client ids
  (`OpenCloudDesktop`, …) which the tsidp UI cannot create — they can be
  injected by hand-editing `oidc-funnel-clients.json` in tsidp's state
  dir (client ids are just map keys there). Until then, desktop users
  should use app tokens (the desktop client supports app-token login).
  Not tested — treat as unsupported.
- tsidp holds sessions in memory: restarting the tsidp container logs
  everyone out of OpenCloud (access tokens live 5 min, refresh tokens
  30 days; re-login via WhoIs is seamless).

### ff (as deployed)

ff (`https://ff.internal.polpetta.online`, the personal finance tracker from
`inputs.ff`) authenticates against tsidp with a hand-rolled flow — no OAuth
library, just `node:crypto` and `fetch` in `src/lib/server/{oidc,session}.ts`:

- Authorization code + PKCE **S256**, token endpoint auth
  `client_secret_post` (tsidp supports it), scopes `openid profile email`
  (everything tsidp offers).
- No local JWT validation: the RS256 ID token is ignored, identity claims
  are read from `/userinfo` with the opaque access token (tsidp access
  tokens are not JWTs anyway).
- Redirect URI (must match the registration exactly):
  `https://ff.internal.polpetta.online/login/callback`

**Authorization is enforced by the app, not the IdP**: every tailnet member
can authenticate at tsidp, but ff only accepts the user with headscale
username `jack` (`ALLOWED_USERNAME` in `src/lib/server/oidc.ts`;
the `username` it reads from `/userinfo` is the short headscale name,
see the claims section); anybody
else who completes the flow gets a styled 403 denial page. The check runs
in the login callback and again in `src/hooks.server.ts` (defense in depth
for sessions minted before a policy change).

Sessions are HMAC-SHA256-signed cookies (`ff_session`, 7 days, HttpOnly /
Secure / SameSite=Lax) over `{sub, username, exp}` — no server-side state.
The login flow (state + PKCE verifier + return path) lives in a second
signed cookie (`ff_oauth`, 10 minutes). Post-login redirects accept only
local paths (open-redirect safe). `src/hooks.server.ts` requires a valid
session for everything except `/login`, `/login/callback`, `/logout` and
`/_app/*` static assets — with adapter-node all writes (form actions) pass
through hooks, so no per-action re-checks are needed.

Client registration in the tsidp admin UI
(`https://idp.internal.polpetta.online`):

- Name: `ff`
- Redirect URI: `https://ff.internal.polpetta.online/login/callback`
- Save: tsidp shows client id + secret **once** — both go into sops:

  ```sh
  # in /workspace/code/nix-secrets, add the ff plaintext keys:
  ff/oauth-client-id=<generated client id>
  ff/oauth-client-secret=<generated client secret>
  # session secret: any long random string, e.g.
  #   openssl rand -base64 32
  ff/session-secret=<long random string>
  ```

  (`services/services/ff.nix` renders them into an `ff-env` template with
  `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` / `SESSION_SECRET` /
  `OIDC_ISSUER` and restarts `nerdctl-ff.service` on rotation.)

Caveat: logout (`/logout`) clears ff's session cookie, but tsidp
authenticates via tailnet WhoIs with no interaction, so the next page load
silently logs the user back in. With a single authorized user this is
harmless — there is no meaningful "logged out" state to protect.

### giuoco-del-divertimento (as deployed)

giuoco-del-divertimento (`https://giuoco.polpetta.online`, the drinking-game
card deck) uses the same hand-rolled flow as ff — authorization code + PKCE
**S256**, `client_secret_post`, scopes `openid profile email`, claims read
from `/userinfo` with the opaque access token (`src/lib/server/{oidc,session}.ts`
in the app repo, duplicated rather than shared).

Unlike every other relying party here, giuoco is **intentionally public**
(`web.access = "public"`, short domain set via `web.domain`): anyone on the
internet can play and read cards, and the login exists only to authorize
writes:

| Action                          | Who                        |
| ------------------------------- | -------------------------- |
| Play, read cards (`GET`, torneo next) | everyone, no login   |
| Add a card (`POST /api/items`)  | any successful tsidp login |

There is **no username restriction**: any tailnet member who completes the
flow gets a session and may add cards. External users simply cannot complete
the login (tsidp is unreachable outside the tailnet), so they stay read-only
by construction. Enforcement lives in the app (`src/lib/server/guard.ts` +
`src/hooks.server.ts`: writes without a session get 401 on `/api/*`, a
redirect to `/login` elsewhere).

Sessions are HMAC-SHA256-signed cookies (`giuoco_session`, 7 days,
HttpOnly / Secure / SameSite=Lax) over `{sub, username, exp}`; the flow
state lives in `giuoco_oauth` (10 minutes). Post-login redirects accept
only local paths.

Client registration in the tsidp admin UI
(`https://idp.internal.polpetta.online`):

- Name: `giuoco`
- Redirect URI: `https://giuoco.polpetta.online/login/callback`
- Save: tsidp shows client id + secret **once** — both go into sops:

  ```sh
  # in /workspace/code/nix-secrets, add the giuoco plaintext keys:
  giuoco/oauth-client-id=<generated client id>
  giuoco/oauth-client-secret=<generated client secret>
  # session secret: any long random string, e.g.
  #   openssl rand -base64 32
  giuoco/session-secret=<long random string>
  ```

  (`services/services/giuoco-del-divertimento.nix` renders them into a
  `giuoco-env` template with `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` /
  `SESSION_SECRET` / `OIDC_ISSUER` and restarts
  `nerdctl-giuoco-del-divertimento.service` on rotation.)

Note: before the public switch the app lived at
`https://giuoco-del-divertimento.internal.polpetta.online`; that hostname is
gone — it is no longer in the generated nginx map, so requests to it hit the
default server and are closed with 444. Use `https://giuoco.polpetta.online`.

## Known limitations

- **STS disabled**: token exchange has no use here (no funnel/SaaS
  clients) and stays off. Node-identity attribution itself does work
  through the reverse proxy via `-trusted-proxy`; registered client
  secrets would work too, but there is no consumer for them.
- **No funnel**: tsidp is unreachable for public SaaS clients.
- **headscale's own `oidc:` block stays off**: `node.expiry: 0` means
  re-authentication never triggers, and new-device enrollment can never
  authenticate via tsidp (chicken-and-egg).
