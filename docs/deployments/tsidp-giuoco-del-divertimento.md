# giuoco-del-divertimento as a tsidp relying party

giuoco-del-divertimento (`https://giuoco-del-divertimento.polpetta.online`,
the drinking-game card deck from the `giuoco-del-divertimento` input) uses
the same hand-rolled flow as ff — authorization code + PKCE S256,
`client_secret_post`, claims read from `/userinfo` (`src/lib/server/
{oidc,session}.ts` in the app repo, duplicated rather than shared with ff).

## Deploy ordering (mandatory)

This flake pins the app through the `giuoco-del-divertimento` input, and
the pin in `flake.lock` can lag the app repo. Deploying this service
before pushing the updated app and bumping the input publishes the vhost
— a **public** one — with **ungated anonymous card adds**, the opposite of
the app commit's security claim. Required order:

1. push the app repo,
2. `nix flake lock --update-input giuoco-del-divertimento`,
3. deploy.

Bump the `ff` and `myPackages` inputs in the same deploy batch. Those two
fail safe (`ff` stays tailnet-only; an unpatched tsidp only breaks OpenCloud
logins, nothing is exposed), but they belong in the same batch —
`myPackages` because OpenCloud login needs the patched tsidp.

## Access model

Unlike every other relying party, giuoco is **intentionally public**
(`web.access = "public"`, short domain via `web.domain` in
`services/services/giuoco-del-divertimento.nix`): anyone on the internet
can play and read cards, and the login exists only to authorize writes.

| Action                               | Who                     |
| ------------------------------------ | ----------------------- |
| Play, read cards (`GET`, torneo next) | everyone, no login      |
| Add a card (`POST /api/items`)        | any successful tsidp login |

There is **no username restriction**: any tailnet member who completes the
flow gets a session and may add cards. External users simply cannot
complete the login (tsidp is unreachable outside the tailnet), so they
stay read-only by construction. Enforcement lives in the app
(`src/lib/server/guard.ts` + `src/hooks.server.ts`: writes without a
session get 401 on `/api/*`, a redirect to `/login` elsewhere).

## tsidp client registration

Admin UI (`https://idp.internal.polpetta.online`):

- Name: `giuoco`
- Redirect URI: `https://giuoco-del-divertimento.polpetta.online/login/callback`

tsidp shows the client id + secret **once** — both go into sops alongside
the session secret (key names in `services/services/giuoco-del-divertimento.nix`).

## Note

Before the public switch the app lived at
`https://giuoco-del-divertimento.internal.polpetta.online`; that hostname
is gone — it is no longer in the generated nginx map, so requests to it
hit the default server and are closed with 444.
