#!/usr/bin/env bash
set -euo pipefail
lib=${UPDATE_COMMON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/update-common.sh}
source "$lib"

PKG=t3code
cd "$(update_repo_root)"
require_cmds nix

old=$(nix_eval t3code.version)
nix_update -F --use-github-releases t3code
build t3code
finish "$old" "$(nix_eval t3code.version)"
