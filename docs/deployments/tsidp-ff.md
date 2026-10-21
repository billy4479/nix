# ff as a tsidp relying party

ff (`https://ff.internal.polpetta.online`, the personal finance tracker
from `inputs.ff`) authenticates against tsidp with a hand-rolled flow in
`src/lib/server/{oidc,session}.ts` of the app repo — no OAuth library,
just `node:crypto` and `fetch`. The flow details (authorization code +
PKCE S256, `client_secret_post`, identity claims from `/userinfo`, signed
session cookies, hook-level access checks) live in the app source; this
file records only the deployment wiring.

- Redirect URI (must match the tsidp registration exactly):
  `https://ff.internal.polpetta.online/login/callback`
- **Authorization is enforced by the app, not the IdP**: every tailnet
  member can authenticate at tsidp, but ff only accepts the user with
  headscale username `jack` — the `ALLOWED_USERNAME` environment variable
  (set in `services/services/ff.nix`; the app fails closed without it).
  The `username` it reads from `/userinfo` is the short headscale name
  under the claims invariant in TSIDP.md. Anybody else completing the
  flow gets a styled 403 denial page.

## tsidp client registration

Admin UI (`https://idp.internal.polpetta.online`):

- Name: `ff`
- Redirect URI: `https://ff.internal.polpetta.online/login/callback`

tsidp shows the client id + secret **once** — both go into sops alongside
the session secret (key names and env rendering in `services/services/ff.nix`):

```sh
# in /workspace/code/nix-secrets:
ff/oauth-client-id=<generated client id>
ff/oauth-client-secret=<generated client secret>
ff/session-secret=<long random string, e.g. openssl rand -base64 32>
```

## Caveat

Logout clears ff's session cookie, but tsidp authenticates via tailnet
WhoIs without interaction, so the next page load silently logs the user
back in. With a single authorized user this is harmless — there is no
meaningful "logged out" state to protect.
