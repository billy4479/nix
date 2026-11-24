#!/usr/bin/env bash
# Attribute logged logical writes on ssd_pool/apps to top-level directories.
set -euo pipefail
export PATH=/run/current-system/sw/bin:/usr/bin:/bin

if [[ $(hostname) != serverone || $EUID != 0 ]]; then
  echo 'Run this script as root on serverone.' >&2
  exit 1
fi

read -r dataset device < <(findmnt -n -o SOURCE,MAJ:MIN --mountpoint /mnt/SSD/apps)
if [[ $dataset != ssd_pool/apps || ! $device =~ ^([0-9]+):([0-9]+)$ ]]; then
  echo 'Expected ssd_pool/apps mounted at /mnt/SSD/apps.' >&2
  exit 1
fi
# Linux dev_t in the kernel uses 20 minor bits.
dev=$(((10#${BASH_REMATCH[1]} << 20) | 10#${BASH_REMATCH[2]}))

bpftrace=$(command -v bpftrace || true)
if [[ -z $bpftrace ]]; then
  bpftrace=/home/billy/.local/state/serverone-diagnostics-bpftrace/bin/bpftrace
fi

# Only top-level directory labels go into the output. Names of files directly
# under the dataset root are not collected. Deeper paths and failed walks are
# grouped as unattributed. These byte counts omit some paths (notably mmap
# writeback) and do not capture pool metadata or device writes.
# shellcheck disable=SC2016 # Dollar-prefixed names belong to bpftrace.
timeout --signal=INT --kill-after=5s 325 "$bpftrace" -e '
  kprobe:vfs_write,
  kprobe:vfs_iter_write
  {
    $file = (struct file *)arg0;
    $inode = $file->f_inode;
    $sb = $inode->i_sb;
    if ($sb->s_dev == (uint64)$1 && $sb->s_magic == 0x2fc12fc1 &&
        ($inode->i_mode & 0xf000) == 0x8000) {
      $root = $sb->s_root;
      $dir = $file->f_path.dentry->d_parent;
      @tracked[tid] = 1;
      $depth = 0;
      while ($dir != 0 && $dir != $root && $depth < 32) {
        $parent = $dir->d_parent;
        if ($parent == $root) {
          @apps[tid] = str($dir->d_name.name, 64);
          @tracked[tid] = 2;
          break;
        }
        if ($parent == $dir) {
          break;
        }
        $dir = $parent;
        $depth++;
      }
    }
  }

  kretprobe:vfs_write,
  kretprobe:vfs_iter_write
  /@tracked[tid]/
  {
    if ((int64)retval > 0) {
      if (@tracked[tid] == 2) {
        $app = @apps[tid];
        @bytes_by_app[$app] = sum((int64)retval);
        @writes_by_app[$app] = count();
      } else {
        @unattributed_bytes = sum((int64)retval);
      }
    }
    delete(@apps, tid);
    delete(@tracked, tid);
  }

  interval:s:300 { exit(); }

  END {
    clear(@apps);
    clear(@tracked);
  }
' "$dev"
