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

## Known limitations

- **STS disabled**: token exchange has no use here (no funnel/SaaS
  clients) and stays off. Node-identity attribution itself does work
  through the reverse proxy via `-trusted-proxy`; registered client
  secrets would work too, but there is no consumer for them.
- **No funnel**: tsidp is unreachable for public SaaS clients.
- **headscale's own `oidc:` block stays off**: `node.expiry: 0` means
  re-authentication never triggers, and new-device enrollment can never
  authenticate via tsidp (chicken-and-egg).
