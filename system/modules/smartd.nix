{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostName = config.networking.hostName;

  cfg = config.services.smartd.telegramNotify;
  longCfg = config.services.smartd.longTestNotify;

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

  # Long self-tests have no start/finish hook in smartd (only `-M exec`
  # for failures), so when longTestNotify is enabled we take them out of
  # the smartd schedule and run them from smart-long-test.timer at the
  # same slot instead: the 15th, so they never coincide with the monthly
  # autoScrub (1st of the month), otherwise the HDDs get ~10h of
  # continuous full-surface reads and overheat.
  shortTestSchedule = "S/../../7/02";
  longTestSchedule = "L/../15/./03";
  testSchedule =
    if longCfg.enable then
      "(${shortTestSchedule})"
    else
      "(${shortTestSchedule}|${longTestSchedule})";

  longTestScript =
    pkgs.writeShellScript "smart-long-test" # sh
      ''
        set -eu

        token="$(cat ${config.sops.secrets.telegram-bot-token.path})"
        chat_id="$(cat ${config.sops.secrets.telegram-bot-chat-id.path})"

        send() {
          ${pkgs.curl}/bin/curl --fail --silent --show-error \
            --request POST \
            "https://api.telegram.org/bot$token/sendMessage" \
            --data-urlencode "chat_id=$chat_id" \
            --data-urlencode "text=$1" \
            > /dev/null || echo "telegram notification failed" >&2
        }

        devices=""
        for dev in $(${pkgs.smartmontools}/bin/smartctl --scan | ${pkgs.coreutils}/bin/cut -d ' ' -f 1); do
          if ${pkgs.smartmontools}/bin/smartctl -H "$dev" > /dev/null 2>&1; then
            devices="$devices $dev"
          fi
        done

        if [ -z "$devices" ]; then
          echo "no SMART-capable devices found" >&2
          exit 0
        fi

        send "Long SMART self-test starting on ${hostName}, devices:$devices"

        for dev in $devices; do
          ${pkgs.smartmontools}/bin/smartctl -t long "$dev" > /dev/null 2>&1 \
            || echo "could not start long test on $dev" >&2
        done

        # Long tests on big HDDs take ~10h; give up after 24h.
        waited=0
        while [ "$waited" -lt 86400 ]; do
          running=0
          for dev in $devices; do
            if ${pkgs.smartmontools}/bin/smartctl -l selftest "$dev" 2> /dev/null \
              | ${pkgs.gnugrep}/bin/grep -qi 'in progress'; then
              running=$((running + 1))
            fi
          done
          if [ "$running" -eq 0 ]; then
            break
          fi
          ${pkgs.coreutils}/bin/sleep 300
          waited=$((waited + 300))
        done

        report=""
        for dev in $devices; do
          result="$(${pkgs.smartmontools}/bin/smartctl -l selftest "$dev" 2> /dev/null \
            | ${pkgs.gnugrep}/bin/grep '^#' \
            | ${pkgs.coreutils}/bin/head -n 1 \
            || true)"
          report="''${report}
        $dev: ''${result:-no result}"
        done

        if [ "$running" -ne 0 ]; then
          send "Long SMART self-test on ${hostName} still in progress after 24h, giving up:''${report}"
        else
          send "Long SMART self-test finished on ${hostName}:''${report}"
        fi
      '';

  # When telegramNotify is disabled (e.g. serverone, where SMART failures
  # are reported by smartctl_exporter through Alertmanager instead) the
  # self-test schedule is kept but no mailer/exec hook is configured.
  autodetectedArgs =
    "-a -o on -S on -s ${testSchedule}"
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

  options.services.smartd.longTestNotify = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to run the monthly long SMART self-test from a systemd timer
        (15th of the month, 03:00, same slot smartd would use) and notify
        Telegram when it starts and finishes, with the per-device result.

        Takes the `L` entry out of the smartd `-s` schedule, so tests are not
        run twice. Independent from {option}`services.smartd.telegramNotify`:
        failures may keep going through Alertmanager while maintenance pings
        go straight to Telegram.
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

    sops.secrets = lib.mkIf (cfg.enable || longCfg.enable) {
      telegram-bot-token.key = "telegram-bot/token";
      telegram-bot-chat-id.key = "telegram-bot/chat-id";
    };

    systemd.services.smart-long-test = lib.mkIf longCfg.enable {
      description = "Run long SMART self-tests and notify Telegram on start/finish";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = longTestScript;
      };
    };

    systemd.timers.smart-long-test = lib.mkIf longCfg.enable {
      description = "Monthly long SMART self-test";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-15 03:00:00";
        Persistent = true;
      };
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
