#!/usr/bin/env bash
# Count SSD leaf write requests by block type. No paths, file contents, or PIDs.
set -euo pipefail
export PATH=/run/current-system/sw/bin:/usr/bin:/bin

if [[ $(hostname) != serverone || $EUID != 0 ]]; then
  echo 'Run this script as root on serverone.' >&2
  exit 1
fi
if [[ $(</sys/module/zfs/version) != 2.4.4-1 || ! -r /sys/kernel/btf/zfs ]]; then
  echo 'This trace needs the checked OpenZFS 2.4.4-1 module and its BTF.' >&2
  exit 1
fi

# Use the binary installed for the first diagnostic if it is not on PATH.
bpftrace=$(command -v bpftrace || true)
if [[ -z $bpftrace ]]; then
  bpftrace=/home/billy/.local/state/serverone-diagnostics-bpftrace/bin/bpftrace
fi

snapshot() {
  date --iso-8601=seconds
  awk '$3 ~ /^sd[a-c]$/ {print $3, "write_sectors=" $10}' /proc/diskstats
}
echo 'Start device counters (512-byte sectors):'
snapshot
# See OpenZFS zio.c: zio_vdev_io_start and include/sys/spa.h: BP_GET_TYPE,
# BP_GET_LEVEL. Count leaf requests before aggregation, including both mirror
# members, and apply the alignment from the same function. Counts are issued
# rather than completed bytes, so +/- in-flight I/O is expected at the edges.
# -1 means no block pointer (e.g. labels and uberblocks); 9 means intent log.
# Level >0 denotes indirect blocks. Level 0 type 19 is ordinary file data.
# shellcheck disable=SC2016 # Dollar-prefixed names belong to bpftrace.
timeout --signal=INT --kill-after=5s 145 "$bpftrace" -e '
  kprobe:zfs:zio_vdev_io_start
  {
    $io = (struct zio *)arg0;
    $vd = $io->io_vd;
    if ($io->io_type == 2 && $vd != 0 && $vd->vdev_children == 0) {
      $pool = str($io->io_spa->spa_name, 24);
      if ($pool == "zroot" || $pool == "ssd_pool") {
        $type = (int64)-1;
        $level = (uint64)0;
        $bp = $io->io_bp;
        if ($bp != 0) {
          $type = (int64)(($bp->blk_prop >> 48) & 255);
          $level = ($bp->blk_prop >> 56) & 31;
        }

        $size = $io->io_size;
        if (($io->io_flags & (1 << 6)) == 0) {
          $align = (uint64)1 << $vd->vdev_top->vdev_ashift;
          $size = ($size + $align - 1) & ~($align - 1);
        }
        @bytes_by_pool_type_level[$pool, $type, $level] = sum($size);
      }
    }
  }
  interval:s:120 { exit(); }
'
echo 'End device counters (512-byte sectors):'
snapshot
