#!/usr/bin/env bash
# Update derper: latest tailscale/tailscale release, including the Go
# vendorHash.
set -euo pipefail
lib=${UPDATE_COMMON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/update-common.sh}
source "$lib"

PKG=derper
cd "$(update_repo_root)"
require_cmds nix

old=$(nix_eval derper.version)
nix_update -F --use-github-releases derper
build derper
finish "$old" "$(nix_eval derper.version)"
