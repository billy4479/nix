#!/usr/bin/env bash
# Update openchamber-web: latest openchamber/openchamber release. Version and
# the src hash live in common.nix, which nix-update cannot reach through the
# inherit in default.nix, so both are rewritten here; the two bun dependency
# hashes in default.nix are then refreshed by rebuilding them.
set -euo pipefail
lib=${UPDATE_COMMON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/update-common.sh}
source "$lib"

PKG=openchamber-web
cd "$(update_repo_root)"
require_cmds curl jq nix

repo=openchamber/openchamber
common=packages/openchamber-web/common.nix
old=$(nix_eval openchamber-web.version)

tag=$(gh_latest_release "$repo")
[[ -n $tag ]] || die "no latest release found for $repo"
new=${tag#v}

# Even when current, rebuild so a previously interrupted update converges.
info "targeting $new, currently $old"
if [[ $new != "$old" ]]; then
  sha=$(gh_api "/repos/$repo/commits/$tag" | jq -r '.sha')
  [[ -n $sha && $sha != "null" ]] || die "could not resolve $tag to a commit"
  nar=$(nix flake prefetch "github:$repo/$sha" --json | jq -r '.hash')
  [[ -n $nar && $nar != "null" ]] || die "could not prefetch $repo@$sha"
  old_hash=$(sed -n 's/ *hash = "\(.*\)";/\1/p' "$common")
  [[ -n $old_hash ]] || die "could not read the src hash from $common"
  sed_replace "$common" "version = \"$old\"" "version = \"$new\""
  sed_replace "$common" "$old_hash" "$nar"
fi

rehash_fod openchamber-web.buildNodeModules packages/openchamber-web/default.nix
rehash_fod openchamber-web.runtimeNodeModules packages/openchamber-web/default.nix
build openchamber-web
finish "$old" "$(nix_eval openchamber-web.version)"
