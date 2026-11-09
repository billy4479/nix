#!/usr/bin/env bash
# Update libvpl-tools: latest intel/libvpl-tools release.
set -euo pipefail
lib=${UPDATE_COMMON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/update-common.sh}
source "$lib"

PKG=libvpl-tools
cd "$(update_repo_root)"
require_cmds nix

old=$(nix_eval libvpl-tools.version)
nix_update -F --use-github-releases libvpl-tools
build libvpl-tools
finish "$old" "$(nix_eval libvpl-tools.version)"
