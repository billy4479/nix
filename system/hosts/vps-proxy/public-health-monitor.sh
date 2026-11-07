#!/bin/sh
# Independent public health monitor for vps-proxy.
#
# Probe the public Headscale health endpoint through the VPS ingress and the
# WireGuard tunnel to serverone, then notify Telegram directly from this host.
# The state machine is deliberately tiny: three consecutive failures alert
# once, the first success after that sends one recovery. It does not depend on
# serverone, Prometheus, Alertmanager, internal DNS or the tailnet.

set -u

state_dir="${STATE_DIR:-/var/lib/public-health-monitor}"
state_file="$state_dir/state"
failure_threshold="${FAILURE_THRESHOLD:-3}"
probe_host="${PROBE_HOST:-headscale.polpetta.online}"
probe_ip="${PROBE_IP:-87.106.25.93}"
probe_path="${PROBE_PATH:-/health}"
probe_timeout="${PROBE_TIMEOUT:-10}"
telegram_token_file="${TELEGRAM_TOKEN_FILE:-/run/secrets/telegram-bot-token}"
telegram_chat_id_file="${TELEGRAM_CHAT_ID_FILE:-/run/secrets/telegram-bot-chat-id}"
telegram_attempts="${TELEGRAM_ATTEMPTS:-3}"
telegram_retry_delay="${TELEGRAM_RETRY_DELAY:-5}"
host_name="${HOST_NAME:-vps-proxy}"

umask 077

if ! mkdir -p "$state_dir"; then
  echo "cannot create state directory $state_dir" >&2
  exit 1
fi
chmod 700 "$state_dir" 2>/dev/null || true

if [ ! -r "$telegram_token_file" ] || [ ! -r "$telegram_chat_id_file" ]; then
  echo "telegram secret files are not readable" >&2
  exit 1
fi

failures=0
alerted=0
if [ -r "$state_file" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
    failures) failures="$value" ;;
    alerted) alerted="$value" ;;
    esac
  done <"$state_file"
fi
case "$failures" in
'' | *[!0-9]*) failures=0 ;;
esac
case "$alerted" in
0 | 1) ;;
*) alerted=0 ;;
esac

save_state() {
  temporary="$state_file.tmp"
  if ! printf 'failures=%s\nalerted=%s\n' "$failures" "$alerted" >"$temporary"; then
    echo "cannot write state file $state_file" >&2
    return 1
  fi
  chmod 600 "$temporary"
  mv -f "$temporary" "$state_file"
}

# Keep secrets out of the command line: curl reads the bot URL from a 0600
# config file, and its error output is discarded.
send_telegram() {
  message="$1"
  token="$(cat "$telegram_token_file")" || return 2
  chat_id="$(cat "$telegram_chat_id_file")" || return 2
  body="$state_dir/telegram-message.$$"
  config="$state_dir/curl-config.$$"

  trap 'rm -f "$body" "$config"' EXIT HUP INT TERM
  printf '%s' "$message" >"$body"
  printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token" >"$config"
  chmod 600 "$body" "$config"

  attempt=1
  while [ "$attempt" -le "$telegram_attempts" ]; do
    if curl --silent --fail --max-time 15 --config "$config" \
      --data-urlencode "chat_id=$chat_id" \
      --data-urlencode "text@$body" >/dev/null 2>&1; then
      rm -f "$body" "$config"
      trap - EXIT HUP INT TERM
      return 0
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -le "$telegram_attempts" ]; then
      sleep "$telegram_retry_delay"
    fi
  done

  rm -f "$body" "$config"
  trap - EXIT HUP INT TERM
  echo "telegram notification failed after $telegram_attempts attempts" >&2
  return 1
}

alert_message() {
  cat <<EOF
PUBLIC ENDPOINT DOWN

Host: $host_name
Endpoint: https://$probe_host$probe_path (pinned to $probe_ip)
Probe result: HTTP ${probe_status}
Consecutive failures: $failures (threshold $failure_threshold)
Time: $now

The public ingress, the WireGuard tunnel or the Headscale service is not answering.
EOF
}

recovery_message() {
  cat <<EOF
PUBLIC ENDPOINT RECOVERED

Host: $host_name
Endpoint: https://$probe_host$probe_path (pinned to $probe_ip)
Probe result: HTTP 200
Time: $now
EOF
}

probe_status="$(
  curl --silent --show-error --ipv4 --max-time "$probe_timeout" \
    --resolve "$probe_host:443:$probe_ip" \
    --output /dev/null --write-out '%{http_code}' \
    "https://$probe_host$probe_path" 2>/dev/null
)" || probe_status=000
case "$probe_status" in
200) healthy=1 ;;
*) healthy=0 ;;
esac

now="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

if [ "$healthy" -eq 1 ]; then
  failures=0
  if [ "$alerted" -eq 1 ]; then
    if send_telegram "$(recovery_message)"; then
      alerted=0
      echo "public endpoint recovered; recovery notification sent"
    else
      echo "public endpoint recovered; recovery notification will be retried" >&2
    fi
  fi
  save_state
  exit $?
fi

failures=$((failures + 1))
if [ "$alerted" -eq 0 ] && [ "$failures" -ge "$failure_threshold" ]; then
  if send_telegram "$(alert_message)"; then
    alerted=1
    echo "public endpoint down; alert notification sent"
  else
    echo "public endpoint down; alert notification will be retried" >&2
  fi
fi
save_state
