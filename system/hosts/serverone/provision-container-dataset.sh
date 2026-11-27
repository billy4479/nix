target=$1 dataset=$2 parent=$3 snapshot=$4
fail() { printf '%s\n' "$*" >&2; exit 1; }

# Multiple references to a named dataset may start at once.
exec 9>/run/serverone-volume-provision.lock
flock 9

[[ $(realpath -m -- "$target") == "$target" ]] || fail "Not a canonical path: $target"
mounted=$(findmnt -nro SOURCE --mountpoint "$target" || true)
[[ $mounted != "$dataset" ]] || exit 0
[[ -z $mounted ]] || fail "Unexpected mount at $target: $mounted"
[[ $(findmnt -nro SOURCE --target "$(realpath -m -- "$(dirname -- "$target")")" 2>/dev/null || true) == "$parent" ]] || {
  # Some new volumes also need new intermediate directories. Find the closest
  # existing ancestor without touching anything until the parent is verified.
  ancestor=$(dirname -- "$target")
  while [[ ! -d $ancestor ]]; do
    ancestor=$(dirname -- "$ancestor")
  done
  [[ $(findmnt -nro SOURCE --target "$ancestor") == "$parent" ]] || fail "Expected $parent underneath $target"
}
if zfs list -H -o name "$dataset" >/dev/null 2>&1; then
  fail "$dataset exists but is not mounted at $target; check it manually"
fi

metadata=()
if [[ -e $target ]]; then
  [[ -d $target ]] || fail "Expected a directory at $target"
  entries=$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)
  [[ -z $entries ]] || fail "$target is populated; migrate it before enabling $dataset"
  owner=$(stat -c %u:%g -- "$target")
  mode=$(stat -c %a -- "$target")
  acl=$(getfacl -cpn -- "$target")
  metadata=("$owner" "$mode" "$acl")
fi

zfs create -o "mountpoint=$target" -o acltype=posix -o xattr=sa \
  -o "com.sun:auto-snapshot=$snapshot" "$dataset"
[[ $(findmnt -nro SOURCE --mountpoint "$target") == "$dataset" ]] || fail "$dataset did not mount at $target"
if ((${#metadata[@]})); then
  chown -- "${metadata[0]}" "$target"
  chmod -- "${metadata[1]}" "$target"
  printf '%s\n' "${metadata[2]}" | setfacl --set-file=- -- "$target"
fi
