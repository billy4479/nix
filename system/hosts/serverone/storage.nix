{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./snapshot-policy.nix) datasets excludedMounts;
  excludedDatasets = lib.genAttrs (lib.attrValues excludedMounts) (_: false);
  intervals = [
    "frequent"
    "hourly"
    "daily"
    "weekly"
    "monthly"
  ];
  zfs = lib.getExe' config.boot.zfs.package "zfs";
  findmnt = lib.getExe' pkgs.util-linux "findmnt";
  snapshotProperty = "com.sun:auto-snapshot";
  checkMounts = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      path: dataset:
      # sh
      ''
        if ! source=$(${findmnt} -nro SOURCE --mountpoint ${lib.escapeShellArg path}) \
          || [ "$source" != ${lib.escapeShellArg dataset} ]; then
          echo "Expected ${dataset} mounted at ${path}; complete the snapshot policy migration first" >&2
          exit 1
        fi
      '') excludedMounts
  );
  applyPolicy = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      dataset: enabled: "enforce ${lib.escapeShellArg dataset} ${lib.boolToString enabled}"
    ) (datasets // excludedDatasets)
  );
in
{
  # Reconcile the live properties even on existing pools where Disko's create
  # options are not reapplied. Fail before taking a parent snapshot if an
  # excluded path is still on the parent rather than on its own dataset.
  systemd.services = lib.genAttrs (map (interval: "zfs-snapshot-${interval}") intervals) (
    unit:
    let
      interval = lib.removePrefix "zfs-snapshot-" unit;
    in
    {
      after = [ "zfs-mount.service" ];
      preStart = # sh
        ''
          set -eu
          ${checkMounts}

          enforce() {
            local dataset="$1" expected="$2" actual override
            actual=$(${zfs} get -Hp -o value ${snapshotProperty} "$dataset")
            if [ "$actual" != "$expected" ]; then
              ${zfs} set ${snapshotProperty}="$expected" "$dataset"
            fi
            # zfstools checks the per-interval override before the base property.
            override=$(${zfs} get -Hp -o value ${snapshotProperty}:${interval} "$dataset")
            if [ "$override" != - ] && [ "$override" != "$expected" ]; then
              ${zfs} set ${snapshotProperty}:${interval}="$expected" "$dataset"
            fi
          }

          ${applyPolicy}
        '';
    }
  );

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
