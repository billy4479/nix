# tsidp (OIDC identity provider)

How `tsidp` is deployed on `serverone` and how it is wired to the existing
headscale, nginx and bind9 stack. Per-application deployment guides (client
registrations, admin-UI walkthroughs, sops keys) live in `deployments/`.

## What it is

`tsidp` is Tailscale's OIDC identity provider: it authenticates users by
checking **which tailnet node their browser connects from** (WhoIs), so there
are no passwords to manage for self-hosted relying parties (RPs). It is only
useful for services inside the tailnet — it cannot be used as the login
provider for new headscale enrollments, and funnel/SaaS scenarios are
impossible by design.

## Architecture

The container (id 25, IP `10.0.1.25`) runs a **patched** `tsidp` from
`myPackages` (the `tsidp` branch of the `nix-packages` repository; the
patches are `headscale-proxy.patch`, `public-clients.patch` and
`browser-rp-cors.patch`, wired into `tsidp/default.nix` — see
[deployments/tsidp-opencloud.md](deployments/tsidp-opencloud.md) for the
purpose of the latter two). The full flag list is in
`services/services/tsidp.nix`; the non-obvious parts and their reasons:

- tsidp assumes it sits directly on the tailnet with
  Tailscale-provisioned TLS, which headscale cannot do, so it listens on
  plain HTTP and TLS terminates on nginx.
- `X-Real-IP` is honored for WhoIs only when the TCP peer is the nginx
  container (`-trusted-proxy`), so identity arrives via the reverse proxy.
- The OIDC issuer (`-server-url`) is a name resolvable through bind9/nginx,
  not the node's MagicDNS name.

Traffic path:

```text
browser -> bind9 (wg/lan view wildcard) -> nginx 10.0.1.6:443 (TLS, tailnet ACL)
        -> tsidp 10.0.1.25:8080
```

WhoIs depends on seeing the browser's real tailnet IP, so serverone runs with
`--snat-subnet-routes=false`: without it, tailnet clients traversing the
advertised `10.0.1.0/24` route arrive at nginx source-NAT'ed and every WhoIs
lookup fails with `peer not found`.

tsidp joins the tailnet as node `idp` (tagged `tag:idp`) via `TS_CONTROL_URL`
through nginx -> headscale. Its tailnet IP is never used for traffic; only
the container IP behind nginx is. The tag comes baked into the preauth key
(`TS_AUTHKEY`): headscale >= 0.29 rejects any registration that combines a
preauth key with client-advertised tags (`-advertise-tags`), so tsidp must
not be given that flag.

## Headscale policy

`policy.mode` is `database`, so policy is applied through the headplane UI.
Two entry kinds: the static `tagOwners` entry and the per-user grants:

- `tagOwners`:
  ```json
  { "tag:idp": ["jack@"] }
  ```
- Grants (adjust `jack@` to the actual headscale LoginName):
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

The grant doubles as the user-mapping source for relying parties: its
`extraClaims` (here `grafana_role`) are embedded into the tokens tsidp
issues to that user, and `includeInUserInfo` mirrors them into `/userinfo`.
Per-user role assignment is done by adding per-user grants with different
`extraClaims` — RPs should restrict access by requiring a claim rather than
trusting any tailnet identity.

`allow_dcr` enables the RFC 7591 dynamic registration endpoint
(`POST /register`), evaluated from the WhoIs of the connecting client — so
DCR only works from the tailnet.

## Setup checklist

1. Add the sops keys: `tsidp/authkey` (the raw preauth key), plus whatever
   each relying party needs (see its guide in `deployments/`). The key names
   and rendered env vars are declared next to each service in
   `services/services/`.
2. Create the preauth key **with the tag baked in**; a tagged key also
   disables node key expiry, which is what we want for a long-lived idp
   node:
   ```sh
   sudo exec-in-container headscale headscale preauthkeys create \
     --user 1 --reusable --expiration 90d --tags tag:idp
   ```
3. Apply the headscale policy above in headplane.
4. Deploy `serverone`; verify the node `idp` appears in headscale, tagged
   `tag:idp`.
5. Open `https://idp.internal.polpetta.online`, register each client (see
   `deployments/`), put the credentials into sops, redeploy.
6. Log in on the relying parties.

## Claims

What tsidp puts in its tokens in this deployment:

- `sub` = `userid:<n>`, where `<n>` is the headscale numeric user id (jack
  `1`, alice `2`, bob `3`, carol `4`) — not a bare number.
- `email` = headscale's **Email field, verbatim** (see the invariant below);
  same value in the ID token and `/userinfo`.
- `username` (in `/userinfo`) and `preferred_username` (in the ID token,
  only granted with the `profile` scope) = the **email local part** — plain
  upstream tsidp semantics (cut before the first `@`), which under the
  invariant equals the short headscale username. WhoIs carries no short
  username, only the email-shaped LoginName; a user without an Email field
  gets no `username`/`preferred_username` claim at all.
- `name` (in `/userinfo`) = headscale's DisplayName (e.g. `Jack`).
- `picture`, `key`, `nid`, `node`, `addresses`, `tailnet`, `uid`: tailscale
  claims, unchanged.
- Any `extraClaims` from the user's headscale grant (e.g. `grafana_role`)
  are in both the ID token and `/userinfo`.

> **REQUIRED INVARIANT — the email local part is the username.** Every
> headscale user's Email must be `<username>@mail.polpetta.online`:
> `jack@mail.polpetta.online` for `jack`. The addresses are unroutable by
> design (no MX); their job is to make the OIDC `username`/
> `preferred_username` claims (upstream tsidp cuts the local part) equal
> the short headscale username that relying parties key on: OpenCloud
> binds accounts by the `email` claim, Jellyfin matches users by
> `preferred_username`, Grafana by the `username` login attribute, and ff
> compares it against `ALLOWED_USERNAME`. tsidp cannot verify this — set
> the Email **at user creation, before the first login** (a user without
> one gets no `username` claim at all), and never change it afterwards: an
> email rename **orphans the OpenCloud account** (the next login misses
> the lookup and autoprovisions a fresh one) and moves every other
> username-keyed mapping. Display names are cosmetic and load-bearing
> nowhere.

## Relying parties

Discovery (`/.well-known/openid-configuration`) is not usable by all RPs —
Grafana and Outline need explicit URLs. Common ground:

- Issuer: `https://idp.internal.polpetta.online`
- Endpoints: `/authorize`, `/token`, `/userinfo`
- Scopes: `openid profile email`
- PKCE: supported; access tokens are opaque strings (not JWTs) — claims
  must be read from `/userinfo` or the ID token.

Registered clients and where the guide lives:

| RP | Public client? | Guide |
| --- | --- | --- |
| Grafana | no | [deployments/tsidp-grafana.md](deployments/tsidp-grafana.md) |
| headplane | no | [deployments/tsidp-headplane.md](deployments/tsidp-headplane.md) |
| Immich | no | [deployments/tsidp-immich.md](deployments/tsidp-immich.md) |
| Jellyfin | no | [deployments/tsidp-jellyfin.md](deployments/tsidp-jellyfin.md) |
| OpenCloud | **yes** (DCR) | [deployments/tsidp-opencloud.md](deployments/tsidp-opencloud.md) |
| ff | no | [deployments/tsidp-ff.md](deployments/tsidp-ff.md) |
| giuoco-del-divertimento | no | [deployments/tsidp-giuoco-del-divertimento.md](deployments/tsidp-giuoco-del-divertimento.md) |
| Outline | no | [deployments/outline.md](deployments/outline.md) |
| game-server-runner | no | [deployments/tsidp-game-server-runner.md](deployments/tsidp-game-server-runner.md) |

## Known limitations

- **STS disabled**: token exchange has no use here (no funnel/SaaS
  clients) and stays off. Node-identity attribution itself works through
  the reverse proxy via `-trusted-proxy`; registered client secrets would
  work too, but there is no consumer for them.
- **No funnel**: tsidp is unreachable for public SaaS clients.
- **headscale's own `oidc:` block stays off**: `node.expiry: 0` means
  re-authentication never triggers, and new-device enrollment can never
  authenticate via tsidp (chicken-and-egg).
- **Sessions are in memory**: restarting the tsidp container logs every
  RP's browser out (access tokens live 5 min, refresh tokens 30 days;
  re-login via WhoIs is seamless, except where auto-relogin is unwanted —
  same as the "logged out" caveats in the RP guides).
