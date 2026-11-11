#!/usr/bin/env bash
# Route each private flake input to its own deploy key, regardless of key comments.
set -euo pipefail
umask 077

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/config"
chmod 600 "$HOME/.ssh/config"

configure_key() {
  local variable=$1 repository=$2
  local alias="github-ci-${repository}" key="$HOME/.ssh/ci-${repository}"
  if [[ -z ${!variable:-} ]]; then
    echo "Missing Actions secret: $variable" >&2
    exit 1
  fi
  touch "$key"
  chmod 600 "$key"
  printf '%s\n' "${!variable}" >"$key"
  ssh-keygen -y -P '' -f "$key" >/dev/null
  cat >>"$HOME/.ssh/config" <<EOF

Host $alias
  HostName github.com
  User git
  IdentityFile $key
  IdentitiesOnly yes
  BatchMode yes
EOF
  # Support both URL forms used by Git and Nix's Git fetcher.
  git config --global --add "url.ssh://git@${alias}/billy4479/${repository}.git.insteadOf" \
    "ssh://git@github.com/billy4479/${repository}.git"
  git config --global --add "url.ssh://git@${alias}/billy4479/${repository}.git.insteadOf" \
    "git@github.com:billy4479/${repository}.git"
}

configure_key NIX_SECRETS_DEPLOY_KEY nix-secrets
configure_key FF_DEPLOY_KEY ff
configure_key CALENDAR_PROXY_DEPLOY_KEY calendar-proxy-v2
configure_key GIUOCO_DEL_DIVERTIMENTO_DEPLOY_KEY giuoco-del-divertimento
configure_key QUOTE_BOT_DEPLOY_KEY quote-bot
