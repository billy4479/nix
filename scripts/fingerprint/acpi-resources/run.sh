#!/usr/bin/env bash
# Query only the reviewed fingerprint ACPI resources, then unload the helper.
set -euo pipefail
umask 077

if [[ $EUID -ne 0 || -z ${SUDO_UID:-} || -z ${SUDO_GID:-} ]]; then
  printf 'Run with sudo from your normal account.\n' >&2
  exit 1
fi

bundle=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cd "$bundle"
if ! sha256sum --check --status SHA256SUMS; then
  printf 'Bundle verification failed; do not load the module.\n' >&2
  exit 1
fi
expected_release=$(<kernel-release)
expected_kernel=$(<kernel-path)
if [[ $(uname -r) != "$expected_release" || $(readlink -f /run/booted-system/kernel) != "$expected_kernel/bzImage" ]]; then
  printf 'Kernel mismatch: this helper was built for %s and %s.\n' "$expected_release" "$expected_kernel" >&2
  exit 1
fi

# _CRS was reviewed in this exact DSDT. A BIOS change requires another review.
expected_dsdt=01654ee28ce0d6054b2dfdc93ce33a06947fe866d97617b8740c1eeb264347bb
if ! printf '%s  %s\n' "$expected_dsdt" /sys/firmware/acpi/tables/DSDT | sha256sum --check --status; then
  printf 'Firmware table mismatch: re-inspect DSDT before using this helper.\n' >&2
  exit 1
fi
sensor=/sys/bus/spi/devices/spi-GXFP5120:00
if [[ ! -d $sensor || -L $sensor/driver || -d /sys/module/gxfp_acpi_resources ]]; then
  printf 'Expected an unbound fingerprint device and an unloaded helper; refusing.\n' >&2
  exit 1
fi

account=$(getent passwd "$SUDO_UID")
IFS=: read -r _ _ _ _ _ user_home _ <<<"$account"
work=$(mktemp -d /tmp/fingerprint-acpi-query.XXXXXXXX)
loaded=0
cleanup() {
  local status=$?
  trap - EXIT
  if [[ $loaded == 1 ]] && ! /run/current-system/sw/bin/rmmod gxfp_acpi_resources; then
    printf 'WARNING: helper unload failed; run sudo rmmod gxfp_acpi_resources.\n' >&2
    status=1
  fi
  rm -rf -- "$work"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

snapshot() {
  local attribute value
  for attribute in messages transfers bytes_tx bytes_rx errors timedout; do
    IFS= read -r value <"$sensor/statistics/$attribute"
    printf '%s=%s\n' "$attribute" "$value"
  done
}

snapshot >"$work/before"
IFS= read -r taint_before </proc/sys/kernel/tainted
printf 'Reading fingerprint _CRS only. Loading an unsigned/out-of-tree module may taint the kernel until reboot.\n'
/run/current-system/sw/bin/insmod "$bundle/gxfp_acpi_resources.ko"
loaded=1
cp -- /sys/module/gxfp_acpi_resources/parameters/report "$work/resources"
/run/current-system/sw/bin/rmmod gxfp_acpi_resources
loaded=0
snapshot >"$work/after"
IFS= read -r taint_after </proc/sys/kernel/tainted

{
  printf 'kernel=%s\nhelper_unloaded=yes\nkernel_taint_before=%s\nkernel_taint_after=%s\n' "$expected_release" "$taint_before" "$taint_after"
  printf '\n--- SPI counters before ---\n'
  printf '%s\n' "$(<"$work/before")"
  printf '\n--- Resolved ACPI resources ---\n'
  printf '%s\n' "$(<"$work/resources")"
  printf '\n--- SPI counters after ---\n'
  printf '%s\n' "$(<"$work/after")"
  if cmp -s "$work/before" "$work/after"; then
    printf '\nspi_counters_unchanged=yes\n'
  else
    printf '\nspi_counters_unchanged=no\n'
    printf 'WARNING: SPI counters changed; investigate before proceeding.\n' >&2
  fi
} >"$work/report.txt"
output=$(mktemp "$user_home/fingerprint-acpi-report.XXXXXXXX.txt")
cp -- "$work/report.txt" "$output"
chown --no-dereference "$SUDO_UID:$SUDO_GID" "$output"
chmod 600 "$output"
printf '\n%s\n' "$(<"$work/resources")"
printf 'Helper unloaded. Private report saved to:\n%s\n' "$output"
