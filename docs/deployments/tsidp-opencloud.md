# OpenCloud as a tsidp relying party

OpenCloud's tsidp switch is configured in `services/services/opencloud.nix`
— every env var there has a comment explaining why it is set, which is the
source of truth. What is not in that file:

- OpenCloud's clients (web, desktop, Android, iOS) are **public OAuth
  clients**: authorization code + PKCE, no client secret. tsidp in the
  pinned build only accepts secret-carrying clients at the token
  endpoint, so two patches live in `nix-packages` (the `tsidp` branch,
  wired into `tsidp/default.nix` after `tsidp/headscale-proxy.patch` —
  update `myPackages` in the flake lock to pick them up):
  - `tsidp/public-clients.patch` — registered clients **without** a
    secret authenticate by `client_id` alone, but only when the
    authorization request carried a PKCE S256 challenge (`code_verifier`
    enforcement is untouched). Clients holding a registered secret keep
    the upstream path. Making a client public is an explicit
    registration choice: DCR with `token_endpoint_auth_method: "none"`
    stores a secret-less client, the admin UI only mints confidential
    ones.
  - `tsidp/browser-rp-cors.patch` — adds every registered client's
    redirect-URI origin to tsidp's csrf protection and reflects CORS
    headers on `/token` and `/userinfo`, so the web SPA can complete the
    flow in the browser (server-side RPs never needed this). Already
    registered clients are trusted again on restart — no
    re-registration needed.
- The web frontend's CSP must allow XHRs to the issuer; the override
  (`cspOverride` in `opencloud.nix`) deep-merges over the embedded one.
- Webfinger discovery is **mandatory** for the web UI to boot (it fails
  closed with "OIDC configuration could not be loaded via webfinger") and
  is served by OpenCloud itself from the same env — no extra setup.
- The tsidp client id is the sops key `opencloud/oidc-client-id`; the
  IDM admin password is `opencloud/idm-admin-password`.
- The built-in **IDM keeps running** (it still holds all accounts and
  auto-provisioning writes new users there); only the built-in `idp`
  service is excluded.
- Access model: `OC_URL` stays public on purpose (share links); every
  *authentication* path requires the tailnet, because the only issuer is
  tsidp and local password auth is disabled. Public share links do not
  touch the IdP and keep working while the underlying resource stays.

## Client registration (via DCR, not the admin UI)

Every client the admin UI creates gets a generated secret; OpenCloud needs
a secret-less public client. Register it with the RFC 7591 dynamic
registration endpoint, which honours `token_endpoint_auth_method: "none"`
(post-patch) and stores the client with an empty secret.

Run the call from a **tailnet source** — e.g. on serverone itself: DCR is
gated by jack's headscale grant (`allow_dcr`), evaluated from the WhoIs of
the connecting client:

```sh
ssh serverone
curl -s -X POST https://idp.internal.polpetta.online/register \
  -H 'Content-Type: application/json' \
  -d '{
    "client_name": "opencloud",
    "redirect_uris": [
      "https://opencloud.polpetta.online/oidc-callback.html",
      "https://opencloud.polpetta.online/oidc-silent-redirect.html"
    ],
    "token_endpoint_auth_method": "none",
    "grant_types": ["authorization_code", "refresh_token"],
    "response_types": ["code"],
    "scope": "openid profile email"
  }'
```

The `201` response carries **no `client_secret`** — record the `client_id`
as the sops key `opencloud/oidc-client-id`. The registered client shows up
in the tsidp admin UI list like any other client and can be deleted there.

## Account resolution

`PROXY_USER_OIDC_CLAIM=email` resolves accounts by the `email` claim
against the IDM's LDAP `mail` attribute — see the comment block in
`services/services/opencloud.nix` and the invariant in
[../TSIDP.md](../TSIDP.md). Consequences not spelled out there:

- The proxy re-applies `displayName`/`mail` from claims on every login
  (`UpdateUserIfNeeded`): editing them in OpenCloud web is undone at the
  next login — set display names on the headscale users instead.
- Renaming a headscale *username* is harmless (the claim email is
  unchanged, and the account is joined by email); renaming the OpenCloud
  account via the graph API has the mirror effect (the next login's
  lookup misses and autoprovision mints a fresh one).
- Auto-provisioned accounts get **fresh random UUIDs** — a fresh account
  can never see an old account's data without a copy.

## Caveats

- tsidp access tokens are opaque strings — that is why the proxy validates
  them through the userinfo endpoint (see the
  `PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD` comment block in
  `services/services/opencloud.nix`).
- tsidp sessions are in-memory: restarting the tsidp container logs
  browser users out.
- Desktop/mobile sync clients expect predefined public client ids
  (`OpenCloudDesktop`, …) which the tsidp UI cannot create; they could be
  injected by hand-editing `oidc-funnel-clients.json` in tsidp's state
  dir. Until then desktop users should use app tokens (the desktop client
  supports app-token login). Not tested — treat as unsupported.

## History (2026-10 migration)

The switch from the built-in IdP happened as "Plan A — zero-copy": headscale
Emails were set first, jack logged into OpenCloud once so
`UpdateUserIfNeeded` synced the stored LDAP `mail` to the new claim, then
`PROXY_USER_OIDC_CLAIM` was flipped to `email` — only that order avoids
autoprovisioning duplicate accounts on login. The 40G of existing data and
all shares stayed untouched; alice/bob/carol auto-provisioned on first
login. Rollback at the time: redeploy the previous closure (`opencloud
init` is a no-op once `opencloud.yaml` exists, so generated config is
never regenerated; the idp service restarts when `OC_EXCLUDE_RUN_SERVICES`
is unset).
