# serverone snapshot policy

Persistent container volumes get one dataset per host path on `serverone`.
In the volume definition, `isCache = true` marks rebuildable data that must
not be automatically snapshotted. The same flag works on `privateNixStore`.
`sharedDataset = "torrent"` references a dataset declared once in
[`snapshot-policy.nix`](../system/hosts/serverone/snapshot-policy.nix). Shared
volumes inherit the named dataset's policy; they cannot set conflicting cache
flags. Secrets, Nix store files, and runtime mounts are not data volumes.

Nix derives dataset names from host paths and rejects collisions and
unresolved overlaps. Inspect the full inventory and rollout status with:

```sh
nix eval --json .#nixosConfigurations.serverone.config.polpetta.volumeDatasetPlan | jq
```

Before starting a container, Nix checks the expected dataset, provisioning
missing datasets only for absent or empty directories. Snapshot jobs reconcile
`com.sun:auto-snapshot`, including interval overrides, and refuse to take a
parent snapshot if an enforced cache is not mounted. Retention is unchanged:
4 frequent, 24 hourly, 7 daily, 4 weekly and 12 monthly snapshots.

## Service audit

Keep snapshots for state whose loss would require a restore or manual recovery.
Split out only paths identified as rebuildable; ZFS cannot exclude directories
from a dataset snapshot.

| Services or storage | Policy |
| --- | --- |
| T3 Code | Keep the home directory and shared workspaces. Exclude the private Nix store and tmp after their dataset split. |
| PostgreSQL, Immich, OpenCloud, Outline | Keep database state, photos/uploads, cloud files, app data, and Valkey state. Exclude only the Immich ML model cache. The live database snapshots are crash recovery points, not a substitute for database backups. |
| Syncthing, Radicale | Keep service state and synced data on the SSD/HDD datasets. Until migrated, shared `/mnt/SSD/agent-config` is on `zroot/root`, outside these snapshots. Its planned dataset is `ssd_pool/agent-config`. Syncthing is not itself a backup. |
| BIND, Headscale, Headplane, tsidp, certbot, nginx | Keep DNS state (including BIND's managed key files under `cache`), identity state and certificate account/config files. Exclude BIND logs and certbot logs/work. Nginx reads certbot's certs; its generated config does not need a snapshot. |
| Jellyfin, Jackett, Byparr, SearXNG | Keep persistent configuration/data; exclude the separately mounted Jellyfin, Byparr and SearXNG caches and Jackett's temporary downloads. |
| Sonarr, Radarr, qBittorrent, Seerr, mircrewrr | Keep app configuration and databases. Keep the existing shared media/torrent dataset as a unit; splitting library files from torrent paths could break hardlinks. |
| Grafana, agent-up, ff, giuoco-del-divertimento, laurea, quote-bot | Keep persistent app directories. |
| Game server runner, Luna Multiplayer | Keep game state, worlds and the runner's HDD backup repository. |
| BentoPDF, calendar-proxy | No app data mounts to snapshot. |
| Generic SMB shares, Time Machine, general VM storage | Keep existing coverage. The disposable agent VM and Android emulator are excluded. |
| NixOS root and host Nix store | No automatic snapshots. Leave manual snapshots (such as blank/install snapshots) alone. |

Do not treat same-pool snapshots as backups. In particular, confirm separate
backups for important database and user data before pruning old snapshots.

## Rollout on the existing host

The initial `pending` list defers enforcement for existing unsplit volumes.
Pending paths stay on their current datasets and retain existing snapshot
coverage. First follow the [workspace cutover commands](SERVERONE_WORKSPACE_CUTOVER.md)
to move the shared workspaces out of the retired OpenChamber path. Then migrate
the T3 Code private store and caches, followed by persistent
volumes in batches. Give databases a separate maintenance window.
Only remove a path from `pending` after migration or confirmation that it can
be provisioned empty. New paths are enforced by default.

Do the migration as root over a separate SSH session, not from T3 Code. This is
an operator-run maintenance step, not a Disko reformat or an activation script.

1. Check pool free space and arrange a staging location on a different pool
   with enough room before moving the Nix stores. Stop the affected consumers
   and direct writers (including T3 Code, its GC timer and agent-config
   migration), and pause the `zfs-snapshot-*` timers during the cutover. Confirm
   no snapshot job is already running. Keep a verified backup of anything that
   cannot simply be rebuilt.
2. For each path in the batch, use the dataset name from the resolved plan.
   Create it with a temporary mountpoint, `acltype=posix`, `xattr=sa` and
   `com.sun:auto-snapshot=false` for caches or `true` for persistent paths.
   Preserve other parent properties by inheritance unless
   intentionally changing them. For paths being preserved, copy and verify the
   full contents and root directory metadata (e.g. `rsync -aHAXS --numeric-ids`
   as root). Where the SSD has insufficient space, stage on another pool first
   and check actual free space again before restoring. A same-pool rename does
   not free space, and snapshots may pin the source blocks even after removal.
   Caches may be rebuilt instead; preserve their directory ownership and mode.
   T3 Code can seed a fresh runtime store, but keep or stage the old stores if
   profiles or legacy agent configuration still refer to them.
3. Remove the original contents from the parent dataset only after verifying
   the migration copy or deciding they are disposable. Do **not** mount a new
   filesystem over a populated source directory or leave a renamed copy in
   `apps`: the parent will continue snapshotting those blocks. Set the new
   dataset's `mountpoint` to its final path and verify it with
   `findmnt --mountpoint <path>`. Repeat for each exclusion.
4. Remove the batch paths from `pending` and switch to the new NixOS
   generation. Restart writers and resume the timers. Verify at least one
   automatic snapshot run: the parent and dedicated persistent datasets
   should get snapshots, and the cache datasets should get none. A new parent
   snapshot may have empty mountpoint directories, but should not contain
   files from the split datasets.

Historical `apps` snapshots still contain the old files until those snapshots
expire or are explicitly pruned. The split itself does not reclaim them.
Do not shorten retention or destroy snapshots as part of the migration.
