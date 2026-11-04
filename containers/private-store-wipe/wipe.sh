privateStoreRoot=$(realpath -e -- "${1:?private store root required}")
limitGib=${2:?size threshold required}

# This is an explicit, destructive opt-in. Refuse ambiguous roots and invalid
# database results rather than turning an error into permission to remove data.
case "$privateStoreRoot" in / | /nix) exit 1 ;; esac
if ! [[ "$limitGib" =~ ^[1-9][0-9]*$ ]] || [ "$limitGib" -gt 1048576 ]; then
  echo "Invalid private-store wipe threshold" >&2
  exit 1
fi
[ ! -L "$privateStoreRoot/nix" ]
database="$privateStoreRoot/nix/var/nix/db/db.sqlite"
[ -f "$database" ] || exit 0
storeBytes=$(sqlite3 -readonly "$database" 'select coalesce(sum(narSize), 0) from ValidPaths;')
[[ "$storeBytes" =~ ^[0-9]+$ ]]
if [ "$storeBytes" -gt "$((limitGib * 1024 * 1024 * 1024))" ]; then
  echo "Private Nix store exceeds the explicitly configured ${limitGib} GiB wipe threshold"
  rm -rf --one-file-system -- "$privateStoreRoot/nix"
fi
