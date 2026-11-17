#!/bin/sh
# Runs only inside the diskless QEMU test machine, never on portatilo.
set -eu
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mode=unknown
IFS= read -r cmdline </proc/cmdline
case " $cmdline " in
*' test_mode=good '*) mode=good ;;
*' test_mode=absent '*) mode=absent ;;
*' test_mode=wrong-hid '*) mode=wrong-hid ;;
esac
trap 'echo "TEST-FAIL:$mode"; poweroff -f' EXIT

case "$mode" in
good)
  insmod /gxfp_acpi_resources.ko
  report=/sys/module/gxfp_acpi_resources/parameters/report
  cat "$report"
  grep -Fx 'device=GXFP5120' "$report"
  grep -Fx 'query=_CRS' "$report"
  grep -Fx 'spi source=\_SB.PC00.SPI1 select=0 speed_hz=10000000 bits=8 polarity=0 phase=0 cs_polarity=0 wire_mode=0' "$report"
  grep -F 'gpio-int source=\_SB.GPI0 pin=279 triggering=1 polarity=0' "$report"
  grep -F 'gpio-io source=\_SB.GPI0 pin=15 ' "$report"
  grep -Fx 'complete=1' "$report"
  if echo overwrite >"$report" 2>/dev/null; then
    echo 'Read-only report unexpectedly accepted a write'
    exit 1
  fi
  rmmod gxfp_acpi_resources
  test ! -d /sys/module/gxfp_acpi_resources
  if insmod /gxfp_acpi_resources.ko report=override; then
    echo 'Read-only module parameter unexpectedly accepted an input value'
    exit 1
  fi
  test ! -d /sys/module/gxfp_acpi_resources
  ;;
absent | wrong-hid)
  if insmod /gxfp_acpi_resources.ko; then
    echo 'Helper loaded without its expected device'
    exit 1
  fi
  test ! -d /sys/module/gxfp_acpi_resources
  ;;
*) exit 1 ;;
esac

echo "TEST-PASS:$mode"
trap - EXIT
poweroff -f
