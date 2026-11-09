#!/usr/bin/env bash
# Update tizenbrew-installer: latest reisxd/TizenBrewInstaller release,
# including the src hash and the npm dependency caches of the UI and of the
# service.
set -euo pipefail
lib=${UPDATE_COMMON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/update-common.sh}
source "$lib"

PKG=tizenbrew-installer
cd "$(update_repo_root)"
require_cmds curl jq nix

file=packages/tizenbrew-installer/default.nix
old=$(nix_eval tizenbrew-installer.version)
new=$(gh_latest_release reisxd/TizenBrewInstaller | sed 's/^v//')
[[ -n $new ]] || die "could not fetch the latest release"

if [[ $old != "$new" ]]; then
  info "updating $old -> $new"
  sed_replace "$file" "version = \"$old\"" "version = \"$new\""
  rehash_fod tizenbrew-installer.src "$file"
  rehash_fod tizenbrew-installer.ui.npmDeps packages/tizenbrew-installer/ui.nix
  rehash_fod tizenbrew-installer.serviceNodeModules.npmDeps "$file"
fi

build tizenbrew-installer
finish "$old" "$(nix_eval tizenbrew-installer.version)"
