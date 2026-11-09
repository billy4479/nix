#!/usr/bin/env bash
# Update opencode: newest anomalyco/opencode version tag (upstream tags 2.x
# without publishing releases), plus the src hash in node-modules.nix and the
# per-system node_modules hash in hashes.json for the current system.
set -euo pipefail
lib=${UPDATE_COMMON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/update-common.sh}
source "$lib"

PKG=opencode
cd "$(update_repo_root)"
require_cmds curl jq nix

repo=anomalyco/opencode
file=packages/opencode/node-modules.nix
old=$(nix_eval opencode.version)

tag=$(gh_latest_tag "$repo")
[[ -n $tag ]] || die "found no version tags on $repo"
new=${tag#v}
if [[ $new != "$old" ]]; then
  info "updating $old -> $new"
  sed_replace "$file" "version = \"$old\"" "version = \"$new\""
  # The version assertion in node-modules.nix compares the fetched tree's
  # package.json against the version, so the src hash must be fixed before
  # anything can build. nix flake prefetch yields the same hash as
  # fetchFromGitHub.
  sha=$(gh_api "/repos/$repo/commits/$tag" | jq -r '.sha')
  [[ -n $sha && $sha != "null" ]] || die "could not resolve $tag to a commit"
  nar=$(nix flake prefetch "github:$repo/$sha" --json | jq -r '.hash')
  [[ -n $nar && $nar != "null" ]] || die "could not prefetch $repo@$sha"
  old_hash=$(sed -n 's/ *hash = "\(.*\)";/\1/p' "$file")
  [[ -n $old_hash ]] || die "could not read the src hash from $file"
  sed_replace "$file" "$old_hash" "$nar"
else
  info "already at $new"
fi

# The src hash is already fixed above, so a mismatch here is the
# node_modules hash for the current system, which lives in hashes.json.
if fod_hash opencode.node_modules; then
  sys=$(nix eval --impure --raw --expr builtins.currentSystem)
  tmp=$(mktemp)
  jq --arg sys "$sys" --arg hash "$FOD_GOT" '.nodeModules[$sys] = $hash' \
    packages/opencode/hashes.json >"$tmp"
  mv "$tmp" packages/opencode/hashes.json
  info "updated hashes.json entry for $sys"
  others=$(jq -r --arg sys "$sys" \
    '[.nodeModules | keys[] | select(. != $sys)] | join(", ")' packages/opencode/hashes.json)
  if [[ -n $others ]]; then
    info "note: hashes.json still lists $others; run this script on those systems too"
  fi
fi

build opencode
finish "$old" "$(nix_eval opencode.version)"
