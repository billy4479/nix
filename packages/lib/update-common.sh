# Shared helpers for the per-package update scripts. This file is sourced,
# never executed. Scripts source it either from ../lib when run from a
# checkout, or via $UPDATE_COMMON when inlined into a passthru.updateScript.

die() {
  printf '%s: error: %s\n' "${PKG:-update}" "$*" >&2
  exit 1
}

info() {
  printf '%s: %s\n' "${PKG:-update}" "$*"
}

require_cmds() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null || die "$cmd is required but not installed"
  done
}

# Repository root: prefer the checkout the calling script lives in, fall back
# to the working directory (that is where a passthru.updateScript runs from).
update_repo_root() {
  local caller_dir root
  caller_dir=$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd -P)
  if root=$(git -C "$caller_dir" rev-parse --show-toplevel 2>/dev/null); then
    printf '%s\n' "$root"
    return
  fi
  if root=$(git rev-parse --show-toplevel 2>/dev/null); then
    printf '%s\n' "$root"
    return
  fi
  die "cannot locate the repository root; run from a checkout of this flake"
}

# nix-update, pulling it from the nixpkgs registry when not installed.
nix_update() {
  if command -v nix-update >/dev/null; then
    nix-update "$@"
  else
    nix run nixpkgs#nix-update -- "$@"
  fi
}

nix_eval() { # attribute expression, e.g. `nix_eval derper.version`
  nix eval --raw ".#$1"
}

gh_api() { # GitHub API path or full URL; honours GITHUB_TOKEN, follows renames
  local url=$1
  if [[ $url != http* ]]; then
    url="https://api.github.com$url"
  fi
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" "$url"
  else
    curl -fsSL "$url"
  fi
}

# Latest stable release tag of a GitHub repo (drafts and prereleases are
# excluded by the API itself).
gh_latest_release() {
  gh_api "/repos/$1/releases/latest" | jq -r '.tag_name // empty'
}

# Newest stable version tag (v-prefixed, no pre-release suffix), for repos
# that push version tags without publishing GitHub releases.
gh_latest_tag() {
  gh_api "/repos/$1/tags?per_page=100" |
    jq -r '.[].name | select(test("^v[0-9]+(\\.[0-9]+)*$"))' |
    sort -V |
    tail -n1
}

# Newest commit on a branch; prints "<sha> <YYYY-MM-DD>".
gh_latest_commit() {
  gh_api "/repos/$1/commits/${2:-HEAD}" |
    jq -r '"\(.sha) \(.commit.committer.date[0:10])"'
}

# Escape a string for literal use in a sed program with `|` delimiters.
_sed_lhs() {
  printf '%s' "$1" | sed 's/[][\\.^$*|]/\\&/g'
}
_sed_rhs() {
  printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

# Replace every occurrence of old with new in file; both are literal text.
sed_replace() { # file old new
  local file=$1 old=$2 new=$3
  [[ $old != "$new" ]] || return 0
  grep -qF -- "$old" "$file" || die "expected to find '$old' in $file"
  sed -i "s|$(_sed_lhs "$old")|$(_sed_rhs "$new")|g" "$file"
}

# Build a fixed-output derivation to discover its real hash. On mismatch sets
# FOD_SPECIFIED and FOD_GOT and returns 0; returns 1 when the hash is already
# correct; dies on any other failure (the build log goes to stderr).
fod_hash() { # attr
  local attr=$1 out
  info "checking hash of .#$attr (this builds the dependency)"
  if out=$(nix build ".#$attr" --no-link 2>&1); then
    info ".#$attr hash is already correct"
    return 1
  fi
  FOD_SPECIFIED=$(sed -n 's/.*specified: *//p' <<<"$out" | head -n1)
  FOD_GOT=$(sed -n 's/.*got: *//p' <<<"$out" | head -n1)
  if [[ -z $FOD_SPECIFIED || -z $FOD_GOT ]]; then
    printf '%s\n' "$out" >&2
    die ".#$attr failed to build, but not because of a hash mismatch"
  fi
  return 0
}

# fod_hash plus in-place replacement of the stale hash in the given file.
rehash_fod() { # attr file
  if fod_hash "$1"; then
    sed_replace "$2" "$FOD_SPECIFIED" "$FOD_GOT"
    info "updated hash of $1"
  fi
}

build() { # flake attribute, e.g. `build derper`
  info "building $1 to verify"
  nix build ".#$1" --no-link
}

# Final report.
finish() { # old-version new-version
  local old=$1 new=$2
  if [[ $old == "$new" ]]; then
    info "already at $new"
  else
    info "updated $old -> $new"
    info "suggested commit: $PKG: update to $new"
  fi
}
