# game-server-runner as a tsidp relying party

game-server-runner (`https://mc-runner.polpetta.online`, the
`inputs.game-server-runner` Rust rewrite of mc-runner, declared in
`services/services/game-server-runner/`) has two login paths:

- **Admin: OIDC against tsidp**, the ff-style hand-rolled flow
  (`src/web/oidc.rs` in the app repo). The callback path is an API route,
  derived from the forwarded Host header — so the redirect follows the
  `web.domain` override and needs no extra env:

  - Redirect URI (must match exactly):
    `https://mc-runner.polpetta.online/api/auth/oidc/callback`
  - The app accepts exactly one identity: `ADMIN_USERNAME` from the env
    (currently `jack`). Admin login only works from the tailnet (tsidp is
    tailnet-only); the admin console lives at `/admin`, and a browser that
    has completed the flow once auto-redirects past the login screen.

- **Friends: Telegram login widget** — no tsidp involvement: the widget's
  signed payload is verified against the bot token, unknown accounts queue
  for approval in the admin panel. The same bot account is the
  notification sender.

## tsidp client registration

Admin UI (`https://idp.internal.polpetta.online`):

- Name: `game-server-runner`
- Redirect URI: `https://mc-runner.polpetta.online/api/auth/oidc/callback`

tsidp shows the client id + secret **once** — both go into sops. All sops
keys (oauth, `telegram-token` / `telegram-username` / `telegram-chat-ids`,
`restic-password`) are listed in the service declaration
(`services/services/game-server-runner/default.nix`), which renders them
into the env/config templates and restarts the unit on rotation.

The OIDC settings must be complete in the env template or the app refuses
to start (fail closed).

## World config

Each world needs a `server.toml` next to the legacy `mc-runner.yml` (the
rewrite reads TOML; see the game-server-runner README for the syntax —
`command`/`args` replace `java_version`/`jar_file`/flags).
