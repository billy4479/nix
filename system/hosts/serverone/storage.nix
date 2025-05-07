{ pkgs, ... }:
{
  # Flags for zfs volumes (is there a way to set them in nix?):
  # - mountpoint=/mnt/whatever
  # - compression=lz4
  # - atime=off
  # - xattrs=sa
  # - acltype=posix
  # - com.sun:auto-snapshot=true

  # https://github.com/nix-community/disko/issues/581#issuecomment-2260602290
  boot.zfs.extraPools = [
    "hdd_pool"
    "ssd_pool"
  ];

  environment.systemPackages = [ pkgs.smartmontools ];

  services = {
    smartd = {
      enable = true;
      # TODO: add notifications
    };

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
