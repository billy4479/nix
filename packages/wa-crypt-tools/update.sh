#!/usr/bin/env bash
# Update wa-crypt-tools: newest commit on ElDavoo/wa-crypt-tools master,
# including the src hash. The version is <pyproject version>-unstable-<date>,
# so bump the base by hand when upstream's pyproject.toml version changes.
set -euo pipefail
lib=${UPDATE_COMMON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/update-common.sh}
source "$lib"

PKG=wa-crypt-tools
cd "$(update_repo_root)"
require_cmds curl jq nix

file=packages/wa-crypt-tools/default.nix
old=$(nix_eval wa-crypt-tools.version)

read -r sha date < <(gh_latest_commit ElDavoo/wa-crypt-tools)
[[ -n $sha && $sha != "null" && -n $date ]] || die "could not fetch the latest commit"
new="0.2.0-unstable-$date"

if [[ $old != "$new" ]]; then
  info "updating $old -> $new ($sha)"
  sed_replace "$file" "version = \"$old\"" "version = \"$new\""
  old_rev=$(sed -n 's/ *rev = "\(.*\)";/\1/p' "$file")
  [[ -n $old_rev ]] || die "could not read the src rev from $file"
  sed_replace "$file" "$old_rev" "$sha"
  rehash_fod wa-crypt-tools.src "$file"
fi

build wa-crypt-tools
finish "$old" "$(nix_eval wa-crypt-tools.version)"
