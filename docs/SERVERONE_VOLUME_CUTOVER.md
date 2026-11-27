# serverone: migrate the remaining container volumes in one window

Use a separate SSH session, not T3 Code. Run the prep steps while services are
up. The maintenance window starts when you stop the container target. The
procedure does not delete snapshots or old data. The shared torrent dataset
and the already migrated workspaces and T3 Code store are not affected.

## 1. Save the old layout and measure the copies

On `serverone` as your normal user, using Bash:

```bash
cd /mnt/SSD/apps/workspaces/nix
work=$(mktemp -d "$HOME/serverone-volumes.XXXXXX")
printf 'Keep this directory: %s\n' "$work"
nix eval --json .#nixosConfigurations.serverone.config.polpetta.volumeDatasetPlan \
  > "$work/layout.json"
jq -r 'to_entries[] | select(.value.enforce == false) |
  [.key, .value.dataset, (if .value.isCache then "false" else "true" end)] | @tsv' \
  "$work/layout.json" > "$work/pending.tsv"
wc -l "$work/pending.tsv"
```

Expect 45 rows before any further migration. The last column is whether to
snapshot the new dataset. Preserve caches too unless you specifically decide
to rebuild them.

```bash
(
  set -euo pipefail
  while IFS=$'\t' read -r path dataset snapshot; do
    bytes=$(sudo du -sx -B1 -- "$path" | cut -f1)
    printf '%s\t%s\t%s\n' "$bytes" "$dataset" "$path"
  done < "$work/pending.tsv"
) | tee "$work/sizes.tsv"
awk -F '\t' '{split($2,a,"/"); size[a[1]]+=$1} END {
  for (pool in size) printf "%s %.1f GiB of files\n", pool, size[pool]/2^30
}' "$work/sizes.tsv"
zfs list -o name,avail,used hdd_pool/apps ssd_pool/apps ssd_pool
zpool list hdd_pool ssd_pool
```

If `du` reports errors or the row counts differ, stop and investigate. The
per-pool sums are estimates, not a promise of physical allocation. Leave
substantial headroom for metadata, compression and dedup differences, and
live pool use. If space is tight, do not start the window without a separate
staging plan. Take and verify independent backups of PostgreSQL, Immich and
OpenCloud data before this migration, and confirm where PostgreSQL's WAL and
any tablespaces live. ZFS snapshots on the same pool aren't a substitute.

## 2. Stage the final NixOS build, without activating it

Only after saving the manifest above, change the `pending` definition in
`system/hosts/serverone/snapshot-policy.nix` to `pending = [ ];`. Review and
commit just that policy change, then stage the build:

```bash
nix build --no-link .#checks.x86_64-linux.server-policy
git diff -- system/hosts/serverone/snapshot-policy.nix
git add system/hosts/serverone/snapshot-policy.nix
git commit -m 'serverone: enforce the remaining dedicated volumes'
readlink -f /run/current-system > "$work/rollback"
stage-serverone && readlink -f "$HOME/.local/state/serverone-deploy/result" > "$work/next"
```

The new generation must not be activated yet. A failed build is not a reason
to continue with an old staged result.

## 3. Stop writers

Pause remote Syncthing edits and any direct writers such as jobs or shares
writing into the listed paths. Stop and verify the database clients before
the database itself. Use `systemctl status` and logs to confirm PostgreSQL
shut down cleanly before copying its files.

```bash
snap=(zfs-snapshot-{frequent,hourly,daily,weekly,monthly})
sudo systemctl stop "${snap[@]/%/.timer}" certbot-renew.timer t3code-nix-gc.timer
systemctl is-active "${snap[@]/%/.service}" || true
sudo systemctl stop certbot-renew.service t3code-nix-gc.service \
  nerdctl-immich-server.service nerdctl-outline.service
sudo systemctl stop all-containers.target
systemctl list-units --type=service --state=active,activating,deactivating 'nerdctl-*'
```

Wait for any scheduled snapshot job to finish. No `nerdctl-*` unit should
still be running or stopping. Don't run `postgresql-init` during the cutover.

## 4. Copy and verify each volume before switching the mount

The helper below deliberately preserves the original as `PATH.pre-zfs` and
stops at the first failure. It requires fresh datasets. For a retry, inspect
`findmnt`, `zfs list` and the retained source, then finish the interrupted row
manually before continuing. Do not recreate or overwrite a verified dataset.

```bash
migrate_volume() (
  set -eu
  path=$1 dataset=$2 snapshot=$3
  stage="/mnt/serverone-volume-stage/${dataset//\//_}"
  sources=$(findmnt -rn -o TARGET)
  if grep -Fxq "$path" <<< "$sources" || grep -Fq "$path/" <<< "$sources"; then
    printf 'Unexpected mount at or beneath %s\n' "$path" >&2
    exit 1
  fi
  sudo test -d "$path"
  sudo test ! -L "$path"
  sudo test ! -e "$path.pre-zfs"
  sudo test ! -L "$path.pre-zfs"
  sudo test ! -e "$stage"
  sudo test ! -L "$stage"
  printf 'Copying %s to %s\n' "$path" "$dataset"
  sudo zfs create -o "mountpoint=$stage" -o acltype=posix -o xattr=sa \
    -o "com.sun:auto-snapshot=$snapshot" "$dataset"
  test "$(findmnt -nro SOURCE --mountpoint "$stage")" = "$dataset"
  sudo rsync -aHAXSx --numeric-ids --info=progress2 "$path/" "$stage/"
  diff=$(sudo rsync -aHAXSxnic --delete --numeric-ids "$path/" "$stage/")
  if [[ -n $diff ]]; then printf '%s\n' "$diff" >&2; exit 1; fi
  sudo mv -T -- "$path" "$path.pre-zfs"
  sudo zfs set "mountpoint=$path" "$dataset"
  test "$(findmnt -nro SOURCE --mountpoint "$path")" = "$dataset"
)

(
  set -eu
  while IFS=$'\t' read -r path dataset snapshot; do
    migrate_volume "$path" "$dataset" "$snapshot"
    printf '%s\t%s\t%s\n' "$path" "$dataset" "$snapshot" >> "$work/migrated.tsv"
  done < "$work/pending.tsv"
  diff -u "$work/pending.tsv" "$work/migrated.tsv"
)
```

`rsync` preserves permissions, numeric owners, ACLs, xattrs, sparse files and
hardlinks **within** each volume. Different datasets cannot share hardlinks.
If you know of cross-volume hardlinks outside the already shared torrent
filesystem, resolve those before migrating. The `--delete` in the verification
command is paired with `-n` and does not actually delete anything.

## 5. Activate and verify before deleting anything

Only proceed if the two manifests match. `activate-system` can start affected
services. Verify PostgreSQL readiness, then Immich and OpenCloud, check Syncthing
and T3 Code, and review failed units. Keep the recovery copies until the checks
are complete. If activation starts the snapshot timers, stop them again while
recovery copies are on the parent filesystem; otherwise snapshots can capture
those copies as well.

```bash
activate-system "$(<"$work/next")"
sudo systemctl stop "${snap[@]/%/.timer}"
sudo systemctl start all-containers.target
systemctl --failed
while IFS=$'\t' read -r path dataset snapshot; do
  test "$(findmnt -nro SOURCE --mountpoint "$path")" = "$dataset" || printf 'Wrong mount: %s\n' "$path"
  test "$(zfs get -H -o value com.sun:auto-snapshot "$dataset")" = "$snapshot" || printf 'Wrong policy: %s\n' "$dataset"
done < "$work/pending.tsv"
```

If rolling back a row **before any writes to the new copy**, stop its writers,
set its new dataset mountpoint back to its staging path, confirm the old path
is no longer a mount, and restore `PATH.pre-zfs` to `PATH`. If a mountpoint
left an empty directory behind, use `rmdir`, never recursive removal. Include
the interrupted row in the inventory. If the new generation was activated,
reactivate the system path in `$work/rollback` after restoring the paths. If
new writes occurred, reconcile the data first; do not roll back blindly.

Review originals with `awk -F '\t' '{print $1 ".pre-zfs"}' "$work/migrated.tsv"`.
Once satisfied, remove or export the recovery copies individually after
checking for nested mounts. Do not run a wildcard recursive delete. Resume
scheduled jobs after cleanup:

```bash
sudo systemctl start "${snap[@]/%/.timer}" certbot-renew.timer t3code-nix-gc.timer
systemctl list-timers 'zfs-snapshot-*' --no-pager
```

After the next timer run, confirm persistent datasets get snapshots and caches
do not. Existing parent snapshots are unchanged.
