{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostName = config.networking.hostName;

  cfg = config.services.smartd.telegramNotify;

  telegramNotify =
    pkgs.writeShellScript "smartd-telegram-notify" # sh
      ''
        set -eu

        token="$(cat ${config.sops.secrets.telegram-bot-token.path})"
        chat_id="$(cat ${config.sops.secrets.telegram-bot-chat-id.path})"

        message="$(${pkgs.coreutils}/bin/cat <<EOF
        SMART alert from ${hostName}

        Host: ${hostName}
        Device: ''${SMARTD_DEVICESTRING:-''${SMARTD_DEVICE:-unknown}}
        Type: ''${SMARTD_DEVICETYPE:-unknown}
        Failure: ''${SMARTD_FAILTYPE:-unknown}
        Subject: ''${SMARTD_SUBJECT:-smartd alert}

        ''${SMARTD_FULLMESSAGE:-''${SMARTD_MESSAGE:-No message provided by smartd.}}
        EOF
        )"

        ${pkgs.curl}/bin/curl --fail --silent --show-error \
          --request POST \
          "https://api.telegram.org/bot$token/sendMessage" \
          --data-urlencode "chat_id=$chat_id" \
          --data-urlencode "text=$message" \
          > /dev/null
      '';

  # When telegramNotify is disabled (e.g. serverone, where SMART failures
  # are reported by smartctl_exporter through Alertmanager instead) the
  # self-test schedule is kept but no mailer/exec hook is configured.
  autodetectedArgs =
    "-a -o on -S on -s (S/../../7/02|L/../01/./03)"
    + lib.optionalString cfg.enable " -m <nomailer> -M exec ${telegramNotify}";
in
{
  options.services.smartd.telegramNotify = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to send SMART failure notifications through Telegram.

        Requires the `telegram-bot` sops secret block (nested `token` and
        `chat-id` keys), shared with the other Telegram consumers.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = hostName != "vps-proxy";
        message = "The smartd module must not be imported on vps-proxy.";
      }
    ];

    sops.secrets = lib.mkIf cfg.enable {
      telegram-bot-token.key = "telegram-bot/token";
      telegram-bot-chat-id.key = "telegram-bot/chat-id";
    };

    services.smartd = {
      enable = true;

      notifications = {
        mail.enable = false;
        wall.enable = false;
        x11.enable = false;
      };

      defaults = {
        monitored = "-a";
        autodetected = autodetectedArgs;
      };
    };

    environment.systemPackages = [ pkgs.smartmontools ];
  };
}
