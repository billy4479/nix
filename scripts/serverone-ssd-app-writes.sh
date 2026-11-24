#!/usr/bin/env bash
# Attribute logical writes on ssd_pool/apps to apps or T3 Code subdirectories.
set -euo pipefail
export PATH=/run/current-system/sw/bin:/usr/bin:/bin

if [[ $(hostname) != serverone || $EUID != 0 ]]; then
  echo 'Run this script as root on serverone.' >&2
  exit 1
fi

case $#:${1:-} in
0:) split_t3code=0 ;;
1:--t3code) split_t3code=1 ;;
*)
  echo "Usage: $0 [--t3code]" >&2
  exit 2
  ;;
esac

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

# Only top-level directory labels go into the default output. --t3code
# reports fixed bucket names for home, nix-root, tmp, and other T3 Code writes.
# No filenames. Deep paths and failed walks may be unattributed. These byte
# counts omit some paths (notably mmap writeback) and pool metadata.
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
      $child = $dir;
      @tracked[tid] = 1;
      $depth = 0;
      while ($dir != 0 && $dir != $root && $depth < 32) {
        $parent = $dir->d_parent;
        if ($parent == $root) {
          $app = str($dir->d_name.name, 64);
          if ($2 == 0) {
            @apps[tid] = $app;
            @tracked[tid] = 2;
          } else if ($app == "t3code") {
            $bucket = 0;
            if ($child != $dir) {
              $subdir = str($child->d_name.name, 16);
              if ($subdir == "home") { $bucket = 1; }
              if ($subdir == "nix-root") { $bucket = 2; }
              if ($subdir == "tmp") { $bucket = 3; }
            }
            @bucket[tid] = $bucket;
            @tracked[tid] = 3;
          }
          break;
        }
        if ($parent == $dir) {
          break;
        }
        $child = $dir;
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
      } else if (@tracked[tid] == 3) {
        // Bucket IDs: 0=other, 1=home, 2=nix-root, 3=tmp.
        @t3code_bytes_by_bucket[@bucket[tid]] = sum((int64)retval);
        @t3code_writes_by_bucket[@bucket[tid]] = count();
      } else if ($2 == 0) {
        @unattributed_bytes = sum((int64)retval);
      }
    }
    delete(@apps, tid);
    delete(@bucket, tid);
    delete(@tracked, tid);
  }

  interval:s:300 { exit(); }

  END {
    clear(@apps);
    clear(@bucket);
    clear(@tracked);
  }
' "$dev" "$split_t3code"
