#!/usr/bin/env bash
# Shared guard/cleanup for the fixed version, readback and provisioning probes.
set -euo pipefail
umask 077
if [[ $EUID -ne 0 || -z ${SUDO_UID:-} || -z ${SUDO_GID:-} ]]; then
  printf 'Run with sudo from your normal account.\n' >&2
  exit 1
fi
exec 9>/run/fingerprint-version-probe.lock
if ! /run/current-system/sw/bin/flock -n 9; then
  printf 'Another fingerprint probe is running; refusing.\n' >&2
  exit 1
fi
bundle=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cd "$bundle"
if ! sha256sum --check --status SHA256SUMS; then
  printf 'Bundle verification failed.\n' >&2
  exit 1
fi
kind=version
if [[ -f probe-kind ]]; then
  if ! grep -Eq '^[0-9a-f]{64}  probe-kind$' SHA256SUMS; then
    printf 'Probe kind is not covered by the manifest.\n' >&2
    exit 1
  fi
  kind=$(<probe-kind)
fi
case $kind in version | readback | provision) ;; *)
  printf 'Unknown probe kind.\n' >&2
  exit 1
  ;;
esac
probe_args=()
if [[ $kind == provision ]]; then
  if [[ $# != 1 || $1 != --replace-psk ]]; then
    printf 'Persistent key replacement is irreversible. Requires explicit --replace-psk.\n' >&2
    exit 1
  fi
  probe_args=(--replace-psk)
elif [[ $# != 0 ]]; then
  printf 'This read-only probe takes no arguments.\n' >&2
  exit 1
fi
binary="$kind-probe"
if ! grep -Eq "^[0-9a-f]{64}  $binary\$" SHA256SUMS; then
  printf 'Probe binary is not covered by the manifest.\n' >&2
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
work=$(mktemp -d "/tmp/fingerprint-$kind.XXXXXXXX")
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
  local saved=0
  if [[ $kind == version ]]; then
    output=$(mktemp "$user_home/fingerprint-version-report.XXXXXXXX.txt")
    if cp -- "$work/report.txt" "$output"; then saved=1; fi
  else
    output=$(mktemp "$user_home/fingerprint-$kind-report.XXXXXXXX.tar.gz")
    if tar -czf "$output" -C "$work" .; then saved=1; fi
  fi
  if [[ $saved == 1 ]] && chown --no-dereference "$SUDO_UID:$SUDO_GID" "$output" && chmod 600 "$output"; then
    grep -E '^(firmware|profile|result|ack_seen|valid_frames|rejected_frames|userspace_gpio_requests|mcu_state|mcu_tls_connected|mcu_locked|key_hash|key_hash_status|wrapped_key|wrapped_key_status|existing_hash|hash_status|observed_hash|new_key|write_ack|write_completion|write_status|write_fragments|payload_bytes)=' "$work/probe.log"
    printf 'Private report saved to (do not paste/upload its contents):\n%s\n' "$output"
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
case $kind in
version)
  printf 'Sending one firmware-version query.\n'
  printf 'No userspace GPIO requests, resets, scans, or key/config writes.\n'
  ;;
readback)
  printf 'Fixed firmware/key readback only. Sensitive replies go into a private archive.\n'
  printf 'No userspace GPIO requests, resets, scans, or key/config writes.\n'
  ;;
provision)
  printf 'Replacing the sensor PSK once. Recovery key: /var/lib/fingerprint-gxfp5120.psk (root-only).\n'
  printf 'The recovery key is synced before upload and never removed by cleanup. No retry.\n'
  printf 'No userspace GPIO requests, resets, scans, TLS, enrollment or configuration writes.\n'
  ;;
esac
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
(
  cd "$work" || exit 1
  limit=15
  if [[ $kind == provision ]]; then limit=20; fi
  /run/current-system/sw/bin/timeout --signal=TERM --kill-after=2 "$limit" "$bundle/$binary" "${probe_args[@]}" "$node"
) >"$work/probe.log" 2>&1
result=$?
set -e
exit "$result"
