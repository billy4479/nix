# Grafana as a tsidp relying party

Grafana's full OAuth config (endpoints, scopes, PKCE, role mapping) is
declared in `services/services/grafana/default.nix` — see there for every
`GF_AUTH_GENERIC_OAUTH_*` value. The mapping rules worth knowing:

- The client id/secret come from the sops keys
  `grafana/oauth-client-id` / `grafana/oauth-client-secret`.
- Roles are read from the `grafana_role` claim (`extraClaims` of the
  user's headscale grant, see the tsidp policy section). `role_attribute_
  strict` rejects any login whose grant carries no `grafana_role` claim —
  so only users with a per-user grant get accounts (currently jack, as
  Admin). Add a grant per user in headplane to admit more.
- Sign-up (`allow_sign_up`) is safe because tsidp only authenticates
  tailnet members and the strict role check gates account creation.
- The local `admin` account remains as password fallback.

## tsidp client registration

Admin UI (`https://idp.internal.polpetta.online`):

- Name: `grafana`
- Redirect URI: `https://grafana.internal.polpetta.online/login/generic_oauth`

Put the client id/secret (shown once) into the sops keys above and redeploy.
