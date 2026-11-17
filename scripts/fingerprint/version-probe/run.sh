#!/usr/bin/env bash
# First live query: bind only GXFP5120, send A8 once, restore binding/override.
set -euo pipefail
umask 077
if [[ $EUID -ne 0 || -z ${SUDO_UID:-} || -z ${SUDO_GID:-} ]]; then
  printf 'Run with sudo from your normal account.\n' >&2
  exit 1
fi
exec 9>/run/fingerprint-version-probe.lock
if ! /run/current-system/sw/bin/flock -n 9; then
  printf 'Another version probe is running; refusing.\n' >&2
  exit 1
fi
bundle=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cd "$bundle"
if ! sha256sum --check --status SHA256SUMS; then
  printf 'Bundle verification failed.\n' >&2
  exit 1
fi
release=$(<kernel-release)
kernel=$(<kernel-path)
if [[ $(uname -r) != "$release" || $(readlink -f /run/booted-system/kernel) != "$kernel/bzImage" ]]; then
  printf 'Kernel identity mismatch; refusing.\n' >&2
  exit 1
fi
dsdt=01654ee28ce0d6054b2dfdc93ce33a06947fe866d97617b8740c1eeb264347bb
if ! printf '%s  %s\n' "$dsdt" /sys/firmware/acpi/tables/DSDT | sha256sum --check --status; then
  printf 'Firmware table mismatch; refusing.\n' >&2
  exit 1
fi
sensor=/sys/bus/spi/devices/spi-GXFP5120:00
expected=/sys/devices/pci0000:00/0000:00:1e.3/pxa2xx-spi.2/spi_master/spi1/spi-GXFP5120:00
if [[ $(readlink -f "$sensor") != "$expected" || -L $sensor/driver ]]; then
  printf 'Expected the reviewed, unbound fingerprint device; refusing.\n' >&2
  exit 1
fi
override=$(<"$sensor/driver_override")
if [[ -n $override && $override != '(null)' ]]; then
  printf 'A driver override already exists; refusing.\n' >&2
  exit 1
fi
account=$(getent passwd "$SUDO_UID")
IFS=: read -r _ _ _ _ _ user_home _ <<<"$account"
work=$(mktemp -d /tmp/fingerprint-version.XXXXXXXX)
: >"$work/probe.log"
override_set=0
binding_attempted=0
loaded_spidev=0
node=not-created
snapshot() {
  local key value
  for key in messages transfers bytes_tx bytes_rx errors timedout; do
    if IFS= read -r value <"$sensor/statistics/$key"; then
      printf '%s=%s\n' "$key" "$value"
    else
      printf '%s=unavailable\n' "$key"
    fi
  done
}
# shellcheck disable=SC2329 # Invoked indirectly by the EXIT trap below.
finish() {
  local result=$? cleanup_failed=0 current output remaining_override
  trap - EXIT
  set +e
  current=$(readlink -f "$sensor/driver")
  if [[ $binding_attempted == 1 && -L $sensor/driver ]]; then
    if [[ $current == /sys/bus/spi/drivers/spidev ]]; then
      printf 'spi-GXFP5120:00\n' >/sys/bus/spi/drivers/spidev/unbind || cleanup_failed=1
    else
      printf 'Unexpected driver appeared; not unbinding it.\n' >>"$work/probe.log"
      cleanup_failed=1
    fi
  fi
  if [[ $override_set == 1 ]]; then
    printf '\n' >"$sensor/driver_override" || cleanup_failed=1
  fi
  if [[ $loaded_spidev == 1 && -d /sys/module/spidev ]]; then
    /run/current-system/sw/bin/rmmod spidev 2>>"$work/probe.log" || cleanup_failed=1
  fi
  remaining_override=$(<"$sensor/driver_override")
  if [[ -L $sensor/driver || (-n $remaining_override && $remaining_override != '(null)') ]]; then
    cleanup_failed=1
  fi
  snapshot >"$work/after"
  {
    printf 'kernel=%s\nnode=%s\nprobe_exit=%s\ncleanup_failed=%s\ndriver_override_after=%s\n' "$release" "$node" "$result" "$cleanup_failed" "${remaining_override:-empty}"
    if [[ -L $sensor/driver ]]; then printf 'fingerprint_unbound=no\n'; else printf 'fingerprint_unbound=yes\n'; fi
    printf '\n--- Before ---\n%s\n' "$(<"$work/before")"
    printf '\n--- Probe ---\n%s\n' "$(<"$work/probe.log")"
    printf '\n--- After ---\n%s\n' "$(<"$work/after")"
  } >"$work/report.txt"
  output=$(mktemp "$user_home/fingerprint-version-report.XXXXXXXX.txt")
  if cp -- "$work/report.txt" "$output" && chown --no-dereference "$SUDO_UID:$SUDO_GID" "$output" && chmod 600 "$output"; then
    grep -E '^(firmware|result|ack_seen|valid_frames|rejected_frames|userspace_gpio_requests)=' "$work/probe.log"
    printf 'Private report saved to:\n%s\n' "$output"
  else
    printf 'Could not save report; scratch data remains in %s\n' "$work" >&2
    exit 1
  fi
  if [[ $cleanup_failed == 1 ]]; then
    printf 'WARNING: cleanup failed. Stop here and return the report; do not retry.\n' >&2
    result=1
  else
    printf 'Temporary fingerprint binding/override restored. No fallback attempted.\n'
  fi
  rm -rf -- "$work"
  exit "$result"
}
trap 'finish' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
snapshot >"$work/before"
printf 'Sending one firmware-version query. No userspace GPIO requests, resets, scans, or key/config writes.\n'
if [[ ! -d /sys/module/spidev ]]; then loaded_spidev=1; fi
/run/current-system/sw/bin/modprobe spidev 2>>"$work/probe.log"
override_set=1
{ printf 'spidev\n' >"$sensor/driver_override"; } 2>>"$work/probe.log"
binding_attempted=1
{ printf 'spi-GXFP5120:00\n' >/sys/bus/spi/drivers/spidev/bind; } 2>>"$work/probe.log"
shopt -s nullglob
for ((attempt = 0; attempt < 30; attempt++)); do
  candidates=()
  for entry in /sys/class/spidev/spidev*; do
    if [[ $(readlink -f "$entry/device") == "$expected" ]]; then candidates+=("$entry"); fi
  done
  if [[ ${#candidates[@]} == 1 ]]; then
    node="/dev/${candidates[0]##*/}"
    if [[ -c $node ]]; then break; fi
  fi
  sleep 0.1
done
if [[ ${#candidates[@]} != 1 || ! -c $node ]]; then
  printf 'Could not identify the fingerprint spidev node.\n' >>"$work/probe.log"
  exit 1
fi
set +e
/run/current-system/sw/bin/timeout --signal=TERM --kill-after=2 10 "$bundle/version-probe" "$node" >"$work/probe.log" 2>&1
result=$?
set -e
exit "$result"
