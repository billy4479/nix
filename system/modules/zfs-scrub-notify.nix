{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostName = config.networking.hostName;

  cfg = config.services.zfs.scrubTelegramNotify;

  autoScrubPools = config.services.zfs.autoScrub.pools;
  zfsPackage = config.boot.zfs.package;

  poolNames =
    if autoScrubPools == [ ] then "all pools" else lib.concatStringsSep " " autoScrubPools;

  # At runtime: the configured pools, or whatever exists when autoScrub
  # is left to scrub everything.
  poolList =
    if autoScrubPools == [ ]
    then "$(${zfsPackage}/bin/zpool list -H -o name)"
    else lib.concatStringsSep " " autoScrubPools;

  scrubNotify =
    pkgs.writeShellScript "zfs-scrub-notify" # sh
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

        case "$1" in
          start)
            send "ZFS scrub starting on ${hostName} (${poolNames})"
            ;;
          stop)
            # ExecStopPost runs on success and failure alike; ExecStart is
            # `zpool scrub -w`, so success here means the scrub completed.
            if [ "''${SERVICE_RESULT:-}" = success ]; then
              results=""
              for pool in ${poolList}; do
                line="$(${zfsPackage}/bin/zpool status "$pool" 2> /dev/null \
                  | ${pkgs.gnugrep}/bin/grep -m 1 'scan: scrub' \
                  || true)"
                results="''${results}
              $pool: ''${line:-no scrub info}"
              done
              send "ZFS scrub finished on ${hostName}:''${results}"
            else
              send "ZFS scrub FAILED on ${hostName} (result: ''${SERVICE_RESULT:-unknown}, exit: ''${EXIT_CODE:-unknown})"
            fi
            ;;
        esac
      '';
in
{
  options.services.zfs.scrubTelegramNotify = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to notify Telegram when the monthly ZFS scrub
        (`services.zfs.autoScrub`) starts and finishes — with the per-pool
        scrub results — or fails.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.zfs.autoScrub.enable;
        message = "services.zfs.scrubTelegramNotify requires services.zfs.autoScrub.";
      }
    ];

    sops.secrets = {
      telegram-bot-token.key = "telegram-bot/token";
      telegram-bot-chat-id.key = "telegram-bot/chat-id";
    };

    systemd.services.zfs-scrub = {
      serviceConfig = {
        ExecStartPre = "${scrubNotify} start";
        ExecStopPost = "${scrubNotify} stop";
      };
    };
  };
}
