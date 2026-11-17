#!/usr/bin/env bash
# Collect existing kernel/firmware information only. No sensor transactions,
# module loading, device binding, GPIO requests, or configuration writes.
set -euo pipefail
umask 077

if [[ $EUID -ne 0 || -z ${SUDO_UID:-} || -z ${SUDO_GID:-} ]]; then
  printf 'Run this script with sudo from your normal account.\n' >&2
  exit 1
fi

account=$(getent passwd "$SUDO_UID")
IFS=: read -r username _ _ _ _ user_home _ <<<"$account"
if [[ ! -d $user_home ]]; then
  printf 'Cannot find the invoking user home directory.\n' >&2
  exit 1
fi

work=$(mktemp -d /tmp/fingerprint-passive.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
cd "$work"
mkdir -p files

# Explicit allowlist: never copy arbitrary ACPI tables, especially MSDM, which
# contains a Windows product key. Raw table dumps stay outside the repository.
copy_file() {
  local source=$1 destination="files$1"
  if [[ -f $source && -r $source ]]; then
    mkdir -p -- "$(dirname -- "$destination")"
    if ! cp -- "$source" "$destination" 2>>collection-errors.txt; then
      printf 'Could not copy %s\n' "$source" >>collection-errors.txt
    fi
  fi
}

{
  printf 'Passive fingerprint diagnostics\n'
  printf 'Collected: '
  date --iso-8601=seconds
  printf 'Host: '
  hostname
  printf 'Kernel: '
  uname -r
  printf 'Invoking account: %s\n' "$username"
  printf '\nNo sensor commands, module loading, device binding, GPIO requests,\n'
  printf 'or persistent configuration changes are performed by this script.\n'
  printf 'The output may contain private platform information; do not publish it.\n'
  printf '\nSPI devices and existing bindings:\n'
  for device in /sys/bus/spi/devices/*; do
    [[ -e $device ]] || continue
    printf '%s -> %s\n' "$device" "$(readlink -f -- "$device")"
    if [[ -L $device/driver ]]; then
      printf '  driver: %s\n' "$(readlink -f -- "$device/driver")"
    else
      printf '  driver: none\n'
    fi
  done
  printf '\nGPIO controller paths:\n'
  for device in /sys/bus/gpio/devices/gpiochip*; do
    [[ -e $device ]] || continue
    printf '%s -> %s\n' "$device" "$(readlink -f -- "$device")"
  done
} >summary.txt

copy_file /sys/firmware/acpi/tables/DSDT
for source in /sys/firmware/acpi/tables/SSDT* /sys/firmware/acpi/tables/dynamic/SSDT*; do
  copy_file "$source"
done

for attribute in sys_vendor product_name product_version bios_vendor bios_version bios_date board_name; do
  copy_file "/sys/class/dmi/id/$attribute"
done

sensor=/sys/bus/spi/devices/spi-GXFP5120:00
for attribute in modalias uevent driver_override waiting_for_supplier; do
  copy_file "$sensor/$attribute"
done
for attribute in hid uid adr cid path status modalias; do
  copy_file "/sys/bus/acpi/devices/GXFP5120:00/$attribute"
done
for source in "$sensor"/statistics/* "$sensor"/power/runtime_* "$sensor"/power/control; do
  copy_file "$source"
done

controller=/sys/bus/pci/devices/0000:00:1e.3
for attribute in vendor device subsystem_vendor subsystem_device class irq uevent power/runtime_status power/control; do
  copy_file "$controller/$attribute"
done
for source in /sys/class/spi_master/spi1/statistics/*; do
  copy_file "$source"
done

# These debugfs files show current pin configuration. Reading them does not
# request lines, select a pin function, or change direction/output values.
copy_file /sys/kernel/debug/gpio
for source in /sys/kernel/debug/pinctrl/*/pins \
  /sys/kernel/debug/pinctrl/*/pinmux-pins \
  /sys/kernel/debug/pinctrl/*/pinconf-pins \
  /sys/kernel/debug/pinctrl/*/gpio-ranges; do
  copy_file "$source"
done
for device in /sys/bus/gpio/devices/gpiochip* /sys/class/gpio/gpiochip*; do
  for attribute in base label ngpio uevent; do
    copy_file "$device/$attribute"
  done
done

if ! dmesg --color=never 2>>collection-errors.txt |
  grep -Ei 'goodix|gxfp|fingerprint|pxa2xx|pinctrl|gpio|intel.*lpss|spi[0-9]|spi-nor' >kernel-filtered.txt; then
  printf 'No matching kernel messages, or dmesg was unavailable.\n' >>collection-errors.txt
fi

# Tar is created in the private root-owned scratch directory, then copied to a
# fresh destination. No existing file is overwritten; the result is user-owned.
tar -czf diagnostics.tar.gz summary.txt collection-errors.txt kernel-filtered.txt files
output=$(mktemp "$user_home/fingerprint-passive.XXXXXXXX.tar.gz")
cp -- diagnostics.tar.gz "$output"
chown --no-dereference "$SUDO_UID:$SUDO_GID" "$output"
chmod 600 "$output"
printf 'Collected passive diagnostics:\n%s\n' "$output"
printf 'No sensor commands or configuration changes were made.\n'
