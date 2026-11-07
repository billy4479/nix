{
  config,
  pkgs,
  ...
}:
let
  # Keep the monitor self-contained: a shell script, curl and a systemd timer.
  # Prometheus, blackbox_exporter and Alertmanager stay on serverone; this host
  # only needs to notice when the public service path is gone and say so.
  monitorScript = pkgs.writeTextFile {
    name = "public-health-monitor";
    executable = true;
    text = builtins.readFile ./public-health-monitor.sh;
  };
in
{
  # The shared telegram-bot secret block lives in the secrets repo. vps-proxy
  # needs its own copy because this alert must not depend on serverone.
  sops.secrets = {
    telegram-bot-token.key = "telegram-bot/token";
    telegram-bot-chat-id.key = "telegram-bot/chat-id";
  };

  systemd.services.public-health-monitor = {
    description = "Probe the public Headscale endpoint and notify Telegram independently";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.curl
      pkgs.coreutils
    ];
    environment = {
      STATE_DIR = "/var/lib/public-health-monitor";
      FAILURE_THRESHOLD = "3";
      PROBE_HOST = "headscale.polpetta.online";
      PROBE_IP = "87.106.25.93";
      PROBE_PATH = "/health";
      PROBE_TIMEOUT = "10";
      TELEGRAM_TOKEN_FILE = config.sops.secrets.telegram-bot-token.path;
      TELEGRAM_CHAT_ID_FILE = config.sops.secrets.telegram-bot-chat-id.path;
      TELEGRAM_ATTEMPTS = "3";
      TELEGRAM_RETRY_DELAY = "5";
      HOST_NAME = "vps-proxy";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = monitorScript;
      StateDirectory = "public-health-monitor";
      StateDirectoryMode = "0700";
      TimeoutStartSec = "2min";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      UMask = "0077";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
    };
  };

  systemd.timers.public-health-monitor = {
    description = "Run the independent public health probe every minute";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
      AccuracySec = "1s";
    };
  };
}
