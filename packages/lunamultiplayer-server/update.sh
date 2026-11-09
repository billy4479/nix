#!/usr/bin/env bash
# Update lunamultiplayer-server: latest LunaMultiplayer release, including the
# nugetDeps lock file, which nix-update regenerates through the fetch-deps
# passthru (this runs a full dotnet restore and needs network access).
set -euo pipefail
lib=${UPDATE_COMMON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/update-common.sh}
source "$lib"

PKG=lunamultiplayer-server
cd "$(update_repo_root)"
require_cmds nix

old=$(nix_eval lunamultiplayer-server.version)
nix_update -F --use-github-releases lunamultiplayer-server
build lunamultiplayer-server
finish "$old" "$(nix_eval lunamultiplayer-server.version)"
