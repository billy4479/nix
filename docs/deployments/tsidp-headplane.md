# headplane as a tsidp relying party

headplane's `oidc:` block (issuer, scopes, PKCE) is in
`services/services/headplane/headplane.yaml`; endpoints are auto-discovered
from the issuer. The client id/secret and other private values are sops keys
rendered into the `headplane-env` template by
`services/services/headplane/default.nix` (headplane merges `HEADPLANE_*__*`
env overrides into its config automatically since 0.7).

What is not in the config:

- The registered client credentials go into the sops keys
  `headplane/oauth-client-id` / `headplane/oauth-client-secret`
- `headplane/cookie-secret`: migrated from the old opaque `headplane-env`
  file.
- `headplane/headscale-api-key`: a server-side headscale API key, created
  with `headscale apikeys create --expiration 999d`. headplane disables
  OIDC entirely without one (it feeds `headscale.api_key`).
- API-key login stays enabled, so the traditional headscale API-key login
  remains as break-glass fallback.

## tsidp client registration

Admin UI (`https://idp.internal.polpetta.online`):

- Name: `headplane`
- Redirect URI (must match exactly — note the `/admin` prefix and **no
  explicit `:443`**, which headplane drops when building the URI from
  `server.base_url`):
  `https://headplane.internal.polpetta.online/admin/oidc/callback`
- Auth method: unset — headplane tries `client_secret_post` first and
  falls back to `client_secret_basic`; tsidp supports both.

## Access model (user decision — containment)

Only jack may *use* headplane, but anyone on the tailnet may *authenticate*:
headplane 0.7.1 has no allow-list, and the first-login Owner bootstrap is
unconditional (verified in source — it overrides even a role claim).
Therefore **jack must complete the first SSO immediately after deploy**,
before anyone else touches the URL; afterwards every other user is a
permanent zero-capability Member (an inert row in the user list). Hard
blocking authentication at the IdP was evaluated (a `restrict_clients`
tsidp grant enforced at `/authorize`) and deliberately skipped as overkill.

The first OIDC user becomes headplane **Owner** and is asked to link their
headscale user during onboarding (link it to `jack@`).
