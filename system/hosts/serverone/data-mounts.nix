{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./snapshot-policy.nix) excludedMounts;
  # These are native ZFS mounts, including datasets managed outside Disko.
  datasets = excludedMounts // {
    "/mnt/HDD/apps" = "hdd_pool/apps";
    "/mnt/HDD/generic" = "hdd_pool/generic";
    "/mnt/HDD/timemachine" = "hdd_pool/timemachine";
    "/mnt/HDD/torrent" = "hdd_pool/torrent";
    "/mnt/SSD/apps" = "ssd_pool/apps";
    "/mnt/SSD/generic" = "ssd_pool/generic";
    "/mnt/SSD/minecraft" = "ssd_pool/minecraft";
    "/mnt/SSD/vm" = "ssd_pool/vm";
  };
  isUnder = mount: path: path == mount || lib.hasPrefix "${mount}/" path;
  mountsFor =
    paths:
    lib.filter (
      mount: lib.any (path: isUnder mount path || (excludedMounts ? ${mount} && isUnder path mount)) paths
    ) (builtins.attrNames datasets);
  requireDatasets =
    mounts:
    lib.mkIf (mounts != [ ]) {
      # Native mounts may not have generated .mount units before ZFS runs.
      after = [ "zfs-mount.service" ];
      unitConfig.RequiresMountsFor = mounts;
      preStart = lib.mkBefore (lib.concatMapStringsSep "\n" checkMount mounts);
    };
  checkMount =
    mount:
    let
      target = lib.escapeShellArg mount;
      expected = lib.escapeShellArg datasets.${mount};
    in
    # sh
    ''
      if ! source=$(${lib.getExe' pkgs.util-linux "findmnt"} --noheadings --raw --output SOURCE --mountpoint ${target}) || [ "$source" != ${expected} ]; then
        echo "Expected ZFS dataset ${datasets.${mount}} at ${mount}; refusing to start" >&2
        exit 1
      fi
    '';
  containerPaths = lib.mapAttrs (
    _: container:
    (map (volume: volume.hostPath) container.volumes)
    ++ lib.optional container.privateNixStore.enable container.privateNixStore.hostPath
  ) config.nerdctl-containers;
in
{
  assertions = lib.mapAttrsToList (name: paths: {
    assertion = lib.all (
      path:
      !(isUnder "/mnt/HDD" path || isUnder "/mnt/SSD" path)
      # Despite its name, /mnt/SSD is a directory on zroot. Agent config
      # intentionally lives there, outside the separate SSD datasets.
      || isUnder "/mnt/SSD/agent-config" path
      || mountsFor [ path ] != [ ]
    ) paths;
    message = "Container ${name} uses a data path not covered by serverone's ZFS mount guards.";
  }) containerPaths;

  systemd.services =
    lib.mapAttrs' (
      name: paths: lib.nameValuePair "nerdctl-${name}" (requireDatasets (mountsFor paths))
    ) containerPaths
    // {
      # Runs before t3code and syncthing and can write to OpenChamber's home.
      agent-config-migration = requireDatasets (mountsFor [
        "/mnt/SSD/apps/openchamber/home"
        "/mnt/SSD/apps/openchamber/nix-root"
      ]);
    };
}
