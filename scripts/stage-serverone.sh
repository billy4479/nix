#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--dry-run|--switch]\nRun on serverone to build the workspace HEAD. Use --switch to activate with sudo.\n' "$0"
}

if (($# > 1)); then
  usage >&2
  exit 2
fi
case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
--dry-run | --switch | '') ;;
*)
  usage >&2
  exit 2
  ;;
esac

if [[ $(hostname -s) != serverone || $EUID == 0 ]]; then
  printf 'Run this on serverone as your normal user, not with sudo.\n' >&2
  exit 1
fi

repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
# The shared checkout belongs to the workspace container user.
workspace_git=(git -c "safe.directory=$repo" -C "$repo")
rev=$("${workspace_git[@]}" rev-parse --verify HEAD)
if [[ -n $("${workspace_git[@]}" status --porcelain) ]]; then
  printf 'Warning: only committed files from HEAD are included.\n' >&2
fi
printf 'Building workspace commit %s on serverone\n' "$rev" >&2

umask 077
snapshot=$(mktemp -d)
trap 'rm -rf -- "$snapshot"' EXIT
"${workspace_git[@]}" archive --format=tar "$rev" | tar -xf - -C "$snapshot"

flake="path:$snapshot#nixosConfigurations.serverone.config.system.build.toplevel"
if [[ ${1:-} == --dry-run ]]; then
  nix build --no-update-lock-file --no-link --dry-run "$flake"
else
  state="$HOME/.local/state/serverone-deploy"
  mkdir -p "$state"
  result=$(nix build --no-update-lock-file --out-link "$state/result" --print-out-paths "$flake")
  if [[ ${1:-} == --switch ]]; then
    activate-system "$result"
  else
    printf '\nTo activate this build (requires sudo):\n  activate-system %s\n' "$result"
  fi
fi
