#!/usr/bin/env bash
# Update tsidp: latest tailscale/tsidp release, including the Go vendorHash.
set -euo pipefail
lib=${UPDATE_COMMON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/update-common.sh}
source "$lib"

PKG=tsidp
cd "$(update_repo_root)"
require_cmds nix

old=$(nix_eval tsidp.version)
nix_update -F --use-github-releases tsidp
build tsidp
finish "$old" "$(nix_eval tsidp.version)"
info "note: the local patches may need adjusting for the new release"
