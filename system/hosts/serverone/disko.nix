{
  # TODO: i dont want to use /dev/sdX in the future, 
  # but at the same time i dont want to post on github my disks serial numbers
  disko.devices = {
    disk = {
      root = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            EFI = {
              size = "256M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
      HDD_1 = {
        type = "disk";
        device = "/dev/sdd";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "hdd_pool";
              };
            };
          };
        };
      };
      HDD_2 = {
        type = "disk";
        device = "/dev/sde";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "hdd_pool";
              };
            };
          };
        };
      };
      HDD_3 = {
        type = "disk";
        device = "/dev/sdf";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "hdd_pool";
              };
            };
          };
        };
      };
      SSD_1 = {
        type = "disk";
        device = "/dev/sdb";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "ssd_pool";
              };
            };
          };
        };
      };
      SSD_2 = {
        type = "disk";
        device = "/dev/sdc";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "ssd_pool";
              };
            };
          };
        };
      };
    };
    zpool = {
      zroot = {
        type = "zpool";
        # mode = "stripe"; # Omitting means stripe??
        # Workaround: cannot import 'zroot': I/O error in disko tests
        options = {
          ashift = "12";
          cachefile = "none";
          autotrim = "on";
        };
        rootFsOptions = {
          # https://wiki.archlinux.org/title/Install_Arch_Linux_on_ZFS
          acltype = "posixacl";
          atime = "off";
          mountpoint = "none";
          xattr = "sa";

          compression = "lz4";
          "com.sun:auto-snapshot" = "false";
        };

        datasets = {
          "local" = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };
          "local/home" = {
            type = "zfs_fs";
            mountpoint = "/home";
            # Used by services.zfs.autoSnapshot options.
            options."com.sun:auto-snapshot" = "true";
          };
          "local/nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options."com.sun:auto-snapshot" = "false";
          };
          "local/root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options."com.sun:auto-snapshot" = "false";
            postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^zroot/local/root@blank$' || zfs snapshot zroot/local/root@blank";
          };
        };
      };
      hdd_pool = {
        type = "zpool";
        mode = "raidz1";
        # Workaround: cannot import 'zroot': I/O error in disko tests
        options = {
          cachefile = "none";
          ashift = "12";
        };
        rootFsOptions = {
          compression = "lz4";
          atime = "off";
          "com.sun:auto-snapshot" = "false";
        };

        postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^hdd_pool@blank$' || zfs snapshot hdd_pool@blank";

        datasets = {
          HDD_generic = {
            type = "zfs_fs";
            options = {
              mountpoint = "/mnt/HDD/generic";
              "com.sun:auto-snapshot" = "true";
            };
          };
        };
      };
      ssd_pool = {
        type = "zpool";
        mode = "mirror";
        # Workaround: cannot import 'zroot': I/O error in disko tests
        options = {
          cachefile = "none";
          autotrim = "on";
          ashift = "12";
        };
        rootFsOptions = {
          compression = "lz4";
          atime = "off";
          "com.sun:auto-snapshot" = "false";
        };

        datasets = {
          SSD_generic = {
            type = "zfs_fs";
            options = {
              mountpoint = "/mnt/SSD/generic";
              "com.sun:auto-snapshot" = "true";
            };
          };
        };
      };
    };
  };
}
