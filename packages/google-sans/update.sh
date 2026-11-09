#!/usr/bin/env bash
# Update google-sans: track the default branch of the font repo, keeping the
# 0-unstable-<date> version format (upstream has no releases).
set -euo pipefail
lib=${UPDATE_COMMON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/update-common.sh}
source "$lib"

PKG=google-sans
cd "$(update_repo_root)"
require_cmds nix

old=$(nix_eval google-sans.version)
nix_update -F --version=branch google-sans
build google-sans
finish "$old" "$(nix_eval google-sans.version)"
