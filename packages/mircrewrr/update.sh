#!/usr/bin/env bash
# Update mircrewrr: newest commit on easly1989/mircrewrr main, including the
# src hash. Upstream publishes no tags, so the version is
# <version reported by the admin API>-unstable-<date>.
set -euo pipefail
lib=${UPDATE_COMMON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/update-common.sh}
source "$lib"

PKG=mircrewrr
cd "$(update_repo_root)"
require_cmds curl jq nix

file=packages/mircrewrr/default.nix
old=$(nix_eval mircrewrr.version)
app_version=${old%-unstable-*}

read -r sha date < <(gh_latest_commit easly1989/mircrewrr)
[[ -n $sha && $sha != "null" && -n $date ]] || die "could not fetch the latest commit"
new="$app_version-unstable-$date"

if [[ $old != "$new" ]]; then
  info "updating $old -> $new ($sha)"
  sed_replace "$file" "version = \"$old\"" "version = \"$new\""
  old_rev=$(sed -n 's/ *rev = "\(.*\)";/\1/p' "$file")
  [[ -n $old_rev ]] || die "could not read the src rev from $file"
  sed_replace "$file" "$old_rev" "$sha"
  rehash_fod mircrewrr.src "$file"
fi

build mircrewrr
finish "$old" "$(nix_eval mircrewrr.version)"
