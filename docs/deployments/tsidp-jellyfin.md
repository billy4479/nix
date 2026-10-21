# Jellyfin as a tsidp relying party

## SSO plugin (declaratively seeded)

The **SSO-Auth** plugin (by 9p4, release `4.0.0.4`) is seeded
declaratively: `services/services/jellyfin.nix` builds the upstream
release zip
into a nix-store layout of
`plugins/SSO-Auth/4.0.0.4/{SSO-Auth,Duende.IdentityModel,Duende.IdentityModel.OidcClient}.dll`
and seeds it into the rw config volume from the `nerdctl-jellyfin` unit's
`preStart` (a root `install` + `chown` to the container user, re-run on
every container start). Jellyfin 12 auto-loads manifest-free plugin
folders (it scans `plugins/*/` recursively for `*.dll` and synthesizes an
`Active` manifest), so nothing has to be installed or updated through the
dashboard — bump the version in `jellyfin.nix` instead.

Two seeding approaches failed and must not be retried:

- A nested **read-only bind** of the store path onto
  `/config/plugins/SSO-Auth` loaded the plugin but crashed the server with
  EROFS: Jellyfin 12 writes `meta.json` next to the plugin dlls on every
  start and the nix store is not writable.
- **tmpfiles** (`C` rules) only apply at boot — `nixos-rebuild switch`
  never runs them — and on this volume they could not run at all anyway:
  systemd's `chase()` aborts canonicalizing any path below `/config`
  because `/mnt/SSD/apps/jellyfin` (uid 5000) and `config/` (uid 5010)
  form an "unsafe path transition" under `CHASE_SAFE`, so the rule was
  skipped silently and the plugin vanished from the plugins page after
  the first deploy without a reboot.

The plugin's provider configuration (which contains the client secret)
lives in Jellyfin's own config volume
(`/config/plugins/configurations/SSO-Auth.xml`) and is done in the admin
UI, below.

## tsidp client registration

Admin UI (`https://idp.internal.polpetta.online`):

- Name: `jellyfin`
- Redirect URI (must match exactly — one line, no trailing slash; the
  plugin builds it from the request's scheme/host behind nginx):
  `https://jellyfin.internal.polpetta.online/sso/OID/r/tsidp`
- Auth method: the plugin's OIDC client sends the secret as a
  token-endpoint POST body parameter (`client_secret_post`, the OidcClient
  default) — supported by tsidp.
- PKCE: the plugin always uses S256, tsidp supports it.

## Admin UI

Dashboard → Plugins → **SSO Authentication** → OpenID tab, add a provider.
Defaults are fine unless noted:

| Field | Value |
| --- | --- |
| Name of OpenID Provider | `tsidp` (this is the `{provider}` in the redirect URI above — they must agree) |
| OpenID Endpoint | `https://idp.internal.polpetta.online/.well-known/openid-configuration` |
| OpenID Client ID / secret | from the tsidp registration (secret shown once) |
| Enabled | **on** |
| Enable Authorization by Plugin | **off** — with this off the plugin never touches permissions: `jack` stays admin, existing users keep their access, and auto-created users get Jellyfin's defaults (non-admin, all libraries, playback enabled). If it were on, every SSO login would demote users unless roles match, and tsidp has no roles to offer |
| Roles / AdminRoles / Role Claim | empty — empty `Roles` is what lets every tailnet identity pass the login gate |
| Request Additional Scopes | `email` (one line; the field is required — the plugin always sends `openid profile` itself, which covers every claim used) |

Save the provider. The plugin does **not** add a button to the login page
by itself; to get one, paste this into Dashboard → General → Branding →
*Login disclaimer*:

```html
<form action="https://jellyfin.internal.polpetta.online/sso/OID/start/tsidp">
  <button class="raised block emby-button button-submit">Sign in with SSO</button>
</form>
```

## Order matters

1. **Before any SSO login**: Dashboard → Users → the username the plugin
   sees is the ID token's `preferred_username` — the short headscale name
   (see the claims invariant in TSIDP.md) — and it matches identities to
   accounts by username, creating a fresh non-admin user when none
   matches. Jack's Jellyfin account must therefore carry his headscale
   username before his first SSO login; otherwise the first login of
   `jack` silently creates a fresh **non-admin** account and admin access
   stays stranded in the old one.
2. Deploy `serverone`, confirm **SSO-Auth** shows as installed in
   Dashboard → Plugins (seeded into the config volume, no catalog entry).
3. Register the tsidp client (above), configure the provider, Save.
4. Verify by logging in through SSO: existing headscale users must land
   in their **existing** Jellyfin accounts (check Dashboard → Users for
   no duplicates); other tailnet members are auto-created with standard
   permissions on first login.

## Caveats

- `tv` and the smart TV keep password/Quick Connect login from the LAN:
  local and password auth stay fully enabled (each user keeps its own
  authentication provider; SSO users created by the plugin are pinned to
  it, everyone else is untouched). `tv` never uses SSO.
- If accounts named after headscale user ids (`userid:1`, `userid:2`, …)
  appear, the ID token had no `preferred_username` (e.g. the registration
  lost the `profile` scope) and the plugin silently fell back to `sub`.
- Break-glass: rename the provider or flip its `Enabled` checkbox off in
  the plugin page — every user falls back to local login.
