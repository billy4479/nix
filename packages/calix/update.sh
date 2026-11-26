#!/usr/bin/env bash
set -euo pipefail
lib=${UPDATE_COMMON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/update-common.sh}
source "$lib"

PKG=calix
cd "$(update_repo_root)"
require_cmds nix

old=$(nix_eval calix.version)
nix_update -F --use-github-releases calix
build calix
finish "$old" "$(nix_eval calix.version)"
