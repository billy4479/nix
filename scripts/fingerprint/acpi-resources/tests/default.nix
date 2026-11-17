{
  runCommand,
  acpica-tools,
  cpio,
  gzip,
  qemu_test,
  pkgsStatic,
  kernel,
  helper,
}:
runCommand "gxfp-acpi-resources-vm-test"
  {
    nativeBuildInputs = [
      acpica-tools
      cpio
      gzip
      qemu_test
    ];
  }
  # sh
  ''
    mkdir -p "$out" initrd/bin initrd/dev initrd/proc initrd/sys
    iasl -p good ${./fixture.asl}
    iasl -D WRONG_HID -p wrong ${./fixture.asl}
    cp ${pkgsStatic.busybox}/bin/busybox initrd/bin/
    for applet in sh mount insmod rmmod cat grep poweroff; do
      ln -s busybox "initrd/bin/$applet"
    done
    cp ${helper}/gxfp_acpi_resources.ko initrd/
    cp ${./init.sh} initrd/init
    chmod 755 initrd/init
    (cd initrd; find . -print0 | cpio --null -o -H newc | gzip -n) > initrd.gz

    for mode in good absent wrong-hid; do
      options=()
      case "$mode" in
        good) options=(-acpitable file=good.aml) ;;
        wrong-hid) options=(-acpitable file=wrong.aml) ;;
      esac
      timeout 150 qemu-system-x86_64 \
        -machine q35 -accel tcg -cpu max -m 512 -smp 1 \
        -nodefaults -display none -monitor none -serial stdio -no-reboot \
        -kernel ${kernel}/bzImage -initrd initrd.gz \
        -append "console=ttyS0 rdinit=/init panic=-1 oops=panic loglevel=4 test_mode=$mode" \
        "''${options[@]}" > "$out/$mode.log" 2>&1
      grep -F "TEST-PASS:$mode" "$out/$mode.log"
    done
    grep -F 'fixed device not found' "$out/absent.log"
    grep -F 'unexpected hardware ID' "$out/wrong-hid.log"
  ''
