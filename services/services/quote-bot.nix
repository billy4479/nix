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
      };

      environmentFiles = [ config.sops.templates."quote-bot-env".path ];

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
