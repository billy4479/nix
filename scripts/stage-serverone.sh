#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--dry-run]\nBuild serverone from the local HEAD without pushing or activating it.\n' "$0"
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
--dry-run | '') ;;
*)
  usage >&2
  exit 2
  ;;
esac

repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
rev=$(git -C "$repo" rev-parse --verify HEAD)
if [[ -n $(git -C "$repo" status --porcelain) ]]; then
  printf 'Warning: only committed files from HEAD are included.\n' >&2
fi
printf 'Sending %s to serverone\n' "$rev" >&2

git -C "$repo" archive --format=tar "$rev" | ssh -T serverone "mode=${1:-build};" '
  set -eu
  umask 077
  snapshot=$(mktemp -d)
  trap '\''rm -rf -- "$snapshot"'\'' EXIT
  tar -xf - -C "$snapshot"

  flake="path:$snapshot#nixosConfigurations.serverone.config.system.build.toplevel"
  if [ "$mode" = --dry-run ]; then
    nix build --no-update-lock-file --no-link --dry-run "$flake"
  else
    state="$HOME/.local/state/serverone-deploy"
    mkdir -p "$state"
    result=$(nix build --no-update-lock-file --out-link "$state/result" --print-out-paths "$flake")
    printf "\nTo activate this build (requires sudo):\n  ssh -t serverone activate-system %s\n" "$result"
  fi
'
