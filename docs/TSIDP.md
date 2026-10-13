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
- a grants entry:
  ```jsonc
  {
    "src": ["jack@"],
    "dst": ["tag:idp"],
    "app": {
      "tailscale.com/cap/tsidp": [
        { "allow_admin_ui": true, "allow_dcr": true }
      ]
    }
  }
  ```

Adjust `jack@` to the actual headscale LoginName. Per-service login
restrictions are done at each RP (e.g. Grafana's
`GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP = "false"`), not in tsidp: it
authenticates any untagged tailnet node's browser for plain OIDC logins.

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

## Known limitations

- **STS disabled**: token exchange has no use here (no funnel/SaaS
  clients) and stays off. Node-identity attribution itself does work
  through the reverse proxy via `-trusted-proxy`; registered client
  secrets would work too, but there is no consumer for them.
- **No funnel**: tsidp is unreachable for public SaaS clients.
- **headscale's own `oidc:` block stays off**: `node.expiry: 0` means
  re-authentication never triggers, and new-device enrollment can never
  authenticate via tsidp (chicken-and-egg).
