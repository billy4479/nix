{
  pkgs,
  vps,
  domain,
}:
let
  service = vps.systemd.services.public-health-monitor;
  timer = vps.systemd.timers.public-health-monitor;
in
assert service.environment.PROBE_HOST == "headscale.${domain}";
assert service.environment.PROBE_IP == "87.106.25.93";
assert service.environment.PROBE_PATH == "/health";
assert service.environment.FAILURE_THRESHOLD == "3";
assert service.serviceConfig.StateDirectory == "public-health-monitor";
assert timer.timerConfig.OnUnitActiveSec == "1min";
assert vps.sops.secrets.telegram-bot-token.key == "telegram-bot/token";
assert vps.sops.secrets.telegram-bot-chat-id.key == "telegram-bot/chat-id";
pkgs.runCommand "public-health-monitor-test"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  # sh
  ''
    cp ${../system/hosts/vps-proxy/public-health-monitor.sh} monitor.sh
    chmod +x monitor.sh
    MONITOR_SCRIPT="$PWD/monitor.sh" python3 ${./public-health-monitor.py} -v
    touch "$out"
  ''
