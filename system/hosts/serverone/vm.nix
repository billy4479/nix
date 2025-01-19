{ pkgs, lib, ... }:
{
  boot = {
    blacklistedKernelModules = [ "i915" ];
    kernelModules = [ "vfio-pci" ];
    kernelParams =
      let
        deviceIds = [
          "8086:9bc8" # Video
          # "8086:f0c8" # Audio
        ];
      in
      [
        "intel_iommu=on"
        "iommu=pt"
        "vfio_pci.ids=${lib.strings.concatStringsSep "," deviceIds}"
      ];

    # # https://forum.proxmox.com/threads/trying-to-blacklist-i915-module-for-use-by-guest-via-pci-passthru.110217/
    # extraModprobeConfig = ''
    #   install i915 ${pkgs.coreutils}/bin/false
    # '';
    #
    # initrd = {
    #   # https://alexbakker.me/post/nixos-pci-passthrough-qemu-vfio.html
    #   availableKernelModules = [ "vfio-pci" ];
    #   preDeviceCommands = # bash
    #     ''
    #       DEVS="0000:00:02.0"
    #       for DEV in $DEVS; do
    #         echo "vfio-pci" > /sys/bus/pci/devices/$DEV/driver_override
    #       done
    #       modprobe -i vfio-pci
    #     '';
    # };
  };

  # https://nixos.wiki/wiki/QEMU
  environment = {
    systemPackages = [
      pkgs.pciutils
      pkgs.qemu
      (pkgs.writeShellScriptBin "qemu-system-x86_64-uefi" ''
                                                              qemu-system-x86_64 \
                                                                -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
  "$@"
      '')
    ];
  };

}
