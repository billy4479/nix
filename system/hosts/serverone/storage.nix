{ ... }:
{
  # Flags for zfs volumes (is there a way to set them in nix?):
  # - mountpoint=/mnt/whatever
  # - compression=lz4
  # - atime=off
  # - xattrs=sa
  # - acltype=posix
  # - com.sun:auto-snapshot=true

  # Cap the ZFS ARC at half of RAM (~16 GiB). Unbounded, the ARC climbs to
  # c_max (~30 GiB) and `free` reports the box as out of memory even though
  # the ARC shrinks under pressure. Services + kernel need ~13 GiB baseline
  # and nightly nix builds spike a further ~7 GiB, so leave that headroom.
  boot.kernelParams = [
    "zfs.zfs_arc_max=${toString (16 * 1024 * 1024 * 1024)}"
  ];

  boot.zfs = {
    forceImportRoot = false;

    # https://github.com/nix-community/disko/issues/581#issuecomment-2260602290
    extraPools = [
      "hdd_pool"
      "ssd_pool"
    ];
  };

  services = {
    zfs = {
      autoScrub = {
        enable = true;
        pools = [
          "hdd_pool"
          "ssd_pool"
          "zroot"
        ];

        interval = "monthly";
      };

      trim.enable = true;

      autoSnapshot = {
        enable = true;
        flags = "-k -p --utc";

        frequent = 4;
        hourly = 24;
        daily = 7;
        weekly = 4;
        monthly = 12;
      };
    };
  };
}
