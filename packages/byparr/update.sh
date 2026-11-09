#!/usr/bin/env bash
# Update byparr: latest ThePhaseless/Byparr release, repinning the fetchTree
# rev + narHash in source.nix and the version in default.nix. Also repins the
# stealthfox engine archive from the source's new invisible-core seal and the
# GeoIP database in geoip.nix to the latest daijro/geoip-all-in-one release.
set -euo pipefail
lib=${UPDATE_COMMON:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/update-common.sh}
source "$lib"

PKG=byparr
cd "$(update_repo_root)"
require_cmds curl jq nix

repo=ThePhaseless/Byparr
old=$(nix_eval byparr.version)

tag=$(gh_latest_release "$repo")
[[ -n $tag ]] || die "no latest release found for $repo"
new=${tag#v}

# Even when current, rebuild so a previously interrupted update converges.
info "targeting $new, currently $old"
sha=$(gh_api "/repos/$repo/commits/$tag" | jq -r '.sha')
[[ -n $sha && $sha != "null" ]] || die "could not resolve $tag to a commit"
nar=$(nix flake prefetch "github:$repo/$sha" --json | jq -r '.hash')
[[ -n $nar && $nar != "null" ]] || die "could not prefetch $repo@$sha"

source_file=packages/byparr/source.nix
old_rev=$(sed -n 's/ *rev = "\(.*\)";/\1/p' "$source_file")
old_nar=$(sed -n 's/ *narHash = "\(.*\)";/\1/p' "$source_file")
[[ -n $old_rev && -n $old_nar ]] || die "could not read the pinned rev/narHash from $source_file"

sed_replace "$source_file" "$old_rev" "$sha"
sed_replace "$source_file" "$old_nar" "$nar"
sed_replace packages/byparr/default.nix "version = \"$old\"" "version = \"$new\""

# Stealthfox engine: the patched Firefox archive is sealed inside the
# invisible-core that the source ships, so the pin is re-derived from the
# (possibly new) seal. Facts are read from the rebuilt python env; a pin
# left stale by an interrupted run fails loudly at the stealthfox seal
# assertion.
sf_file=packages/byparr/stealthfox.nix
sf_old_url=$(sed -n 's/ *url = "\(.*\)";/\1/p' "$sf_file")
sf_old_hash=$(sed -n 's/ *hash = "\(.*\)";/\1/p' "$sf_file")
sf_old_up=$(sed -n 's/ *version = "\(.*\)";/\1/p' "$sf_file")
[[ -n $sf_old_url && -n $sf_old_hash && -n $sf_old_up ]] ||
  die "could not read the pinned engine url/hash/version from $sf_file"

sf_pyenv=$(nix build --no-link --print-out-paths .#byparr-python-env)
sf_facts=$("$sf_pyenv/bin/python" -c '
import json, platform, sys
from invisible_core.seal import active_seal
seal = active_seal()
asset = seal.asset_for(sys.platform, platform.machine())
print(json.dumps({
    "tag": seal.tag,
    "upstream": seal.upstream_version,
    "name": asset.name,
    "sha256": asset.sha256,
}))
')
sf_fact() { printf '%s' "$sf_facts" | jq -r ".$1"; }
sf_tag=$(sf_fact tag)
sf_name=$(sf_fact name)
sf_new_hash=$(nix hash convert --hash-algo sha256 --to sri "$(sf_fact sha256)")
sf_new_url=${sf_old_url%/download/*}/download/$sf_tag/$sf_name
sf_new_up=$(sf_fact upstream)

if [[ $sf_new_url != "$sf_old_url" || $sf_new_hash != "$sf_old_hash" || $sf_new_up != "$sf_old_up" ]]; then
  info "engine targeting $sf_tag/$sf_name"
  # Hash first: an interrupted run leaves the old url under the new hash,
  # which fetchurl rejects at the next build instead of silently keeping
  # the stale archive.
  sed_replace "$sf_file" "$sf_old_hash" "$sf_new_hash"
  sed_replace "$sf_file" "$sf_old_url" "$sf_new_url"
  sed_replace "$sf_file" "version = \"$sf_old_up\"" "version = \"$sf_new_up\""
fi

# GeoIP database: a dated daijro/geoip-all-in-one release. The new file is
# prefetched to learn its hash: a fetchurl FOD cannot report a URL-only
# change, since its store path only depends on the pinned hash. The hash is
# rewritten first so an interrupted run fails loudly on the next build
# instead of silently keeping the stale database.
geoip_file=packages/byparr/geoip.nix
geoip_old_url=$(sed -n 's/ *url = "\(.*\)";/\1/p' "$geoip_file")
geoip_old_hash=$(sed -n 's/ *hash = "\(.*\)";/\1/p' "$geoip_file")
geoip_old=$(sed -n 's|.*/releases/download/\([^/]*\)/geoip-aio-all\.mmdb.*|\1|p' "$geoip_file")
[[ -n $geoip_old_url && -n $geoip_old_hash && -n $geoip_old ]] ||
  die "could not read the pinned url/hash from $geoip_file"
new_geoip=$(gh_latest_release daijro/geoip-all-in-one)
[[ -n $new_geoip ]] || die "no latest release found for daijro/geoip-all-in-one"
if [[ $new_geoip != "$geoip_old" ]]; then
  info "geoip targeting $new_geoip, currently $geoip_old"
  geoip_new_url=${geoip_old_url//"$geoip_old"/$new_geoip}
  geoip_new_hash=$(nix store prefetch-file --json "$geoip_new_url" | jq -r '.hash')
  [[ -n $geoip_new_hash && $geoip_new_hash != "null" ]] || die "could not prefetch $geoip_new_url"
  sed_replace "$geoip_file" "$geoip_old_hash" "$geoip_new_hash"
  sed_replace "$geoip_file" "$geoip_old" "$new_geoip"
fi

build byparr
finish "$old" "$new"
