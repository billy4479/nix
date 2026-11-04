#!/usr/bin/env bash
# Read-only storage diagnostics. Run on serverone as root; outputs go to billy.
set -uo pipefail
export PATH=/run/current-system/sw/bin:/usr/bin:/bin
umask 077

if (( EUID != 0 )); then
  echo "Run this script with sudo on serverone." >&2
  exit 1
fi
if [[ $(hostname) != serverone ]]; then
  echo "This script is intended for serverone only." >&2
  exit 1
fi

owner=billy
home=$(getent passwd "$owner" | cut -d: -f6)
group=$(id -gn "$owner")
if [[ -z $home || ! -d $home ]]; then
  echo "Cannot find billy's home directory." >&2
  exit 1
fi
output=$(mktemp -d "$home/serverone-write-diagnostics.XXXXXXXX")
finish() {
  # The fresh directory stays root-only until collection is finished.
  chown -R --no-dereference "$owner:$group" "$output"
  echo "Diagnostics saved to: $output"
}
trap finish EXIT

capture() {
  local name=$1
  shift
  local status=0
  "$@" >"$output/$name.txt" 2>&1 || status=$?
  echo "$name: exit $status" >>"$output/status.txt"
}

echo "Collecting read-only diagnostics in $output"
{
  date --iso-8601=seconds
  uname -sr
  uptime
  free -h
  echo "No file contents, process arguments or environment variables collected."
  echo "SMART reports contain disk serial numbers. Keep these files private."
  echo "Disk counters measure host writes, not internal NAND programming."
} >"$output/summary.txt"

capture disks lsblk -d -o NAME,MODEL,SIZE,ROTA
capture pool-health zpool status -P
capture dataset-space zfs list -o name,used,usedbysnapshots,usedbydataset,compressratio,mountpoint
capture dataset-properties zfs get -t filesystem -r -H -o name,property,value,source \
  com.sun:auto-snapshot,atime,compression,sync,recordsize,logbias hdd_pool ssd_pool zroot
for disk in sda sdb sdc; do
  capture "smart-$disk" timeout 30 smartctl -x "/dev/$disk"
done

bpftrace=/home/billy/.local/state/serverone-diagnostics-bpftrace/bin/bpftrace
if [[ ! -x $bpftrace ]]; then
  bpftrace=$(command -v bpftrace || true)
fi

date --iso-8601=seconds >"$output/measurement-start.txt"
cat /proc/diskstats >"$output/diskstats-start.txt"
capture process-names ps -eo pid,ppid,user,comm
capture filesystem-map findmnt -rn -t zfs,tmpfs -o MAJ:MIN,SOURCE,TARGET

# Capture the same one-minute workload window in parallel.
capture process-io timeout 75 pidstat -d 5 12 &
pidstat_job=$!
capture disk-io timeout 75 iostat -dxm -y 5 12 &
iostat_job=$!
if [[ -n $bpftrace ]]; then
  # Count regular files only, separating RAM-backed files from ZFS. Map keys:
  # process name, PID, filesystem magic, device major, device minor.
  # ZFS magic is 0x2fc12fc1; tmpfs magic is 0x01021994.
  # No file names or contents. mmap and other write paths may be missed;
  # asynchronous workers may appear by name. This is logical write volume,
  # not physical write amplification.
  # shellcheck disable=SC2016 # Dollar-prefixed names belong to bpftrace.
  capture logical-writes timeout --signal=INT --kill-after=5s 90 "$bpftrace" -e '
    kprobe:vfs_write,
    kprobe:vfs_iter_write
    {
      $inode = ((struct file *)arg0)->f_inode;
      if (($inode->i_mode & 0xf000) == 0x8000) {
        @tracked[tid] = 1;
        @magic[tid] = $inode->i_sb->s_magic;
        @device[tid] = $inode->i_sb->s_dev;
      }
    }
    kretprobe:vfs_write,
    kretprobe:vfs_iter_write
    /@tracked[tid]/
    {
      if ((int64)retval > 0) {
        $dev = @device[tid];
        @written_bytes[comm, pid, @magic[tid], $dev >> 20, $dev & 1048575] = sum(retval);
      }
      delete(@tracked, tid);
      delete(@magic, tid);
      delete(@device, tid);
    }
    interval:s:60
    {
      exit();
    }
    END
    {
      clear(@tracked);
      clear(@magic);
      clear(@device);
    }
  ' &
  trace_job=$!
else
  echo "bpftrace unavailable; logical write tracing skipped." >"$output/logical-writes.txt"
  trace_job=
fi
wait "$pidstat_job"
wait "$iostat_job"
if [[ -n $trace_job ]]; then
  wait "$trace_job"
fi
cat /proc/diskstats >"$output/diskstats-end.txt"
date --iso-8601=seconds >"$output/measurement-end.txt"
echo "Collection complete. Check status.txt for unsupported or failed commands."
