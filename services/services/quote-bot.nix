{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  name = "quote-bot";
  baseDir = "/mnt/SSD/apps/${name}";
in
{
  # sops keys (in secrets-repo, serverone.yaml), rendered into the env
  # template below, values of the old vercel .env:
  # - quote-bot/telegram-token
  # - quote-bot/webhook-secret
  # - quote-bot/chat-polpetta
  # - quote-bot/chat-quotebook
  # DATABASE_PATH is not secret and set in the container environment.
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    quote-bot-telegram-token.key = "quote-bot/telegram-token";
    quote-bot-webhook-secret.key = "quote-bot/webhook-secret";
    quote-bot-chat-polpetta.key = "quote-bot/chat-polpetta";
    quote-bot-chat-quotebook.key = "quote-bot/chat-quotebook";
  };

  sops.templates."quote-bot-env".content = lib.mkIf (options ? nerdctl-containers) (
    # sh
    ''
      TELEGRAM_BOT_TOKEN=${config.sops.placeholder."quote-bot-telegram-token"}
      TELEGRAM_WEBHOOK_SECRET=${config.sops.placeholder."quote-bot-webhook-secret"}
      CHAT_POLPETTA=${config.sops.placeholder."quote-bot-chat-polpetta"}
      CHAT_QUOTEBOOK=${config.sops.placeholder."quote-bot-chat-quotebook"}
    ''
  );

  sops.templates."quote-bot-env".restartUnits = lib.mkIf (options ? nerdctl-containers) [
    "nerdctl-${name}.service"
  ];

  polpetta.services.${name} = {
    container = {
      id = 26;

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";

        copyToRoot = with pkgs; [
          dockerTools.caCertificates
          quote-bot
        ];

        config.entrypoint = [ "/bin/quote-bot" ];
      };

      environment = {
        PORT = "4479";
        DATABASE_PATH = "/data/quotebot.db";
        # Only the preStart reads this (the setWebhook call); the bot
        # itself serves whatever path Telegram posts to.
        TELEGRAM_WEBHOOK_URL = "https://quote-bot.polpetta.online";
      };

      environmentFiles = [ config.sops.templates."quote-bot-env".path ];

      # Re-register the telegram webhook on every (re)start: the URL is
      # config-owned, so a deploy re-points the bot with no manual
      # setwebhook.sh step. Failures are non-fatal but loud: the
      # registration lives on telegram's side and the next restart
      # retries.
      extraPreStart =
        let
          envFile = config.sops.templates."quote-bot-env".path;
        in
        # sh
        ''
          source ${lib.escapeShellArg envFile}

          # printf is a bash builtin, so the secrets never land in the
          # process list; curl reads the body from a private file.
          umask 077
          body="$STATE_DIRECTORY/setwebhook-body"
          printf 'url=%s/api/webhook&secret_token=%s' \
            "$TELEGRAM_WEBHOOK_URL" "$TELEGRAM_WEBHOOK_SECRET" >"$body"
          response=$(
            ${pkgs.curl}/bin/curl -s --max-time 10 \
              -d @"$body" \
              "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/setWebhook"
          ) && echo "setWebhook: $response" \
            || echo "setWebhook failed (non-fatal), telegram keeps the previous url"
          rm -f "$body"
        '';

      volumes = [
        {
          hostPath = baseDir;
          containerPath = "/data";
        }
      ];
    };

    web = {
      port = 4479;
      # Telegram posts the webhook from the outside, so the endpoint is
      # public; the webhook secret keeps randoms out.
      access = "public";
      # The webhook itself only answers POST; probe the health endpoint.
      probe.path = "/api/healthz";
    };
  };
}
