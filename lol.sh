#!/bin/sh

sudo qemu-system-x86_64-uefi \
    -nodefaults \
    -name "win11" \
    -enable-kvm \
    -m 8G \
    -cpu host,kvm=on \
    -smp 4 \
    -drive file=/mnt/SSD/vm/win11.img,if=virtio,cache=writeback \
    -cdrom /mnt/HDD/generic/win11.iso \
    -device vfio-pci,host=00:02.0,x-vga=on \
    -vga none \
    -display none \
    -monitor stdio \
    -usb -device usb-tablet \
    -netdev user,id=net0 -device e1000,netdev=net0 \
    -boot d

#  -device vfio-pci,host=00:1f.3 \
