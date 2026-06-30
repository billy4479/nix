{
  config,
  pkgs,
  ...
}:
let
  hostName = config.networking.hostName;

  telegramNotify =
    pkgs.writeShellScript "smartd-telegram-notify" # sh
      ''
        set -eu

        . ${config.sops.secrets.smartd-telegram-env.path}

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
          "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
          --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
          --data-urlencode "text=$message"
      '';
in
{
  assertions = [
    {
      assertion = hostName != "vps-proxy";
      message = "The smartd module must not be imported on vps-proxy.";
    }
  ];

  sops.secrets.smartd-telegram-env = { };

  services.smartd = {
    enable = true;

    notifications = {
      mail.enable = false;
      wall.enable = false;
      x11.enable = false;
    };

    defaults = {
      monitored = "-a -o on -S on -s (S/../../7/02|L/../01/./03) -m <nomailer> -M exec ${telegramNotify}";
      autodetected = config.services.smartd.defaults.monitored;
    };
  };

  environment.systemPackages = [ pkgs.smartmontools ];
}
