# serverone workspace cutover

Run these commands over a separate SSH session, **not in T3 Code**. Stopping
T3 Code ends its sessions. Pause work in the synced folders until cutover is
verified. Host paths change, but the paths seen by T3 Code and Syncthing do not.

## 1. Check and build before stopping anything

On `serverone`, as your normal user:

```bash
old=/mnt/SSD/apps/openchamber/workspaces
new=/mnt/SSD/apps/workspaces
git -c "safe.directory=$old/nix" -C "$old/nix" log -1 --oneline
sudo test -s /mnt/SSD/agent-config/AGENTS.md
sudo ls -la /mnt/SSD/agent-config/skills
sudo du -xsh "$old"
zfs list -o name,avail,used ssd_pool/apps
findmnt -nro TARGET | grep -F "$old/" || true
```

Confirm the checkout contains the workspace cutover commit, shared instructions
and skills are already in place, there is space for the copy, and there are no
nested mounts under the old workspace. Do not proceed if any check fails.

```bash
rollback=$(readlink -f /run/current-system)
stage-serverone                      # build only, using the old checkout
next=$(readlink -f "$HOME/.local/state/serverone-deploy/result")
printf 'Rollback: %s\nNext: %s\n' "$rollback" "$next"
```

If this is a retry and the installed staging command already expects the new
path, build using another checkout of the same commit instead. Keep both
printed store paths. Do not proceed if the build fails.

## 2. Stop writers, create the new dataset, and copy

In the same Bash session:

```bash
sudo systemctl stop t3code-nix-gc.timer t3code-nix-gc.service \
  nerdctl-t3code.service nerdctl-syncthing.service
```

Confirm the units are inactive and there are no host-side writers. Only run
this block if the target and dataset are new. If retrying with an existing
dataset, verify its mount and skip creation.

```bash
(
  set -e
  sudo test ! -e "$new"
  sudo test ! -L "$new"
  sudo zfs create -o "mountpoint=$new" -o acltype=posix -o xattr=sa \
    -o com.sun:auto-snapshot=true ssd_pool/apps/workspaces
  test "$(findmnt -nro SOURCE --mountpoint "$new")" = ssd_pool/apps/workspaces
  sudo rsync -aHAXSx --numeric-ids --info=progress2 "$old/" "$new/"
  sudo rsync -aHAXSxnic --delete --numeric-ids "$old/" "$new/"
)
```

The last command is a **dry run**, including its `--delete` flag. It should
print no differences. The old tree remains intact for rollback. Tags, Git
metadata, permissions, hardlinks within the workspace, and Syncthing marker
files are copied. If the verification reports differences, stop here.

## 3. Activate and verify

```bash
activate-system "$next"
sudo systemctl start nerdctl-syncthing.service nerdctl-t3code.service t3code-nix-gc.timer
systemctl is-active nerdctl-syncthing.service nerdctl-t3code.service
findmnt -nro SOURCE --mountpoint "$new"
git -c "safe.directory=$new/nix" -C "$new/nix" status --short
```

Confirm Syncthing shows the same folders without errors, and open a T3 Code
session to check that `/workspace/code` and `/workspace/nix` have their old
contents. Before users resume writes, rollback is:

```bash
sudo systemctl stop nerdctl-syncthing.service nerdctl-t3code.service
activate-system "$rollback"
sudo systemctl start nerdctl-syncthing.service nerdctl-t3code.service t3code-nix-gc.timer
```

After new writes, do not switch back to the old copy without reconciling them.

## 4. Remove the retired tree after verification

First rename it out of the old path to catch any remaining consumers:

```bash
sudo mv -T --no-clobber /mnt/SSD/apps/openchamber /mnt/SSD/apps/openchamber.retired
```

Once verified and you no longer need the rollback copy, delete only that
retired tree. Check for mounts first; if the check lists anything, stop and
inspect it manually.

```bash
findmnt -rn -o TARGET | grep -E '^/mnt/SSD/apps/openchamber\.retired(/|$)' || true
sudo du -xsh /mnt/SSD/apps/openchamber.retired
sudo rm -rf --one-file-system -- /mnt/SSD/apps/openchamber.retired
```

Do not delete `/mnt/SSD/agent-config`. The legacy-named `openchamber-ssh-key`
is also still used by T3 Code. Old snapshots can still retain retired data;
these commands do not prune snapshots.
