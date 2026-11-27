{
  config,
  lib,
  pkgs,
  ...
}:
let
  layout = import ./volume-layout.nix {
    inherit lib;
    containers = config.nerdctl-containers;
  };
  inherit (layout)
    active
    mounts
    refs
    unique
    ;
  byPath = lib.listToAttrs (map (spec: lib.nameValuePair spec.path spec) unique);
  findmnt = lib.getExe' pkgs.util-linux "findmnt";
  args = lib.escapeShellArgs;
  exact = path: dataset: ''
    if [ "$(${findmnt} -nro SOURCE --mountpoint ${lib.escapeShellArg path})" != ${lib.escapeShellArg dataset} ]; then
      echo ${lib.escapeShellArg "Expected ${dataset} mounted at ${path}"} >&2
      exit 1
    fi
  '';
  provision = pkgs.writeShellApplication {
    name = "provision-container-dataset";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.util-linux
      pkgs.coreutils
      pkgs.findutils
      pkgs.acl
    ];
    text = builtins.readFile ./provision-container-dataset.sh;
  };
  guard =
    provisionMissing:
    { spec, hostPath }:
    exact spec.parent mounts.${spec.parent}
    + lib.optionalString (active spec) (
      lib.optionalString (provisionMissing && !spec.existing) ''
        ${lib.getExe provision} ${
          args [
            spec.path
            spec.dataset
            mounts.${spec.parent}
            (lib.boolToString (!spec.isCache))
          ]
        }
      ''
      + exact spec.path spec.dataset
      + lib.optionalString (hostPath != spec.path) ''
        if [ -e ${lib.escapeShellArg hostPath} ] && \
          [ "$(${findmnt} -nro SOURCE --target ${lib.escapeShellArg hostPath})" != ${lib.escapeShellArg spec.dataset} ]; then
          echo ${lib.escapeShellArg "${hostPath} must be on ${spec.dataset}"} >&2
          exit 1
        fi
      ''
    );
  require =
    provisionMissing: rs:
    lib.mkIf (rs != [ ]) {
      after = [ "zfs-mount.service" ];
      unitConfig.RequiresMountsFor = lib.unique (
        lib.concatMap (
          { spec, ... }:
          [ spec.parent ] ++ lib.optional (active spec) spec.path
        ) rs
      );
      preStart = lib.mkBefore (lib.concatMapStrings (guard provisionMissing) rs);
    };
  at = hostPath: {
    inherit hostPath;
    spec = byPath.${hostPath};
  };
in
{
  options.polpetta.volumeDatasetPlan = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    readOnly = true;
    description = "Resolved serverone ZFS volumes and their rollout status.";
  };
  config = {
    inherit (layout) assertions;
    system.build.containerDatasetProvision = provision;
    polpetta.volumeDatasetPlan = lib.mapAttrs (_: spec: spec // { enforce = active spec; }) byPath;
    systemd.services =
      lib.mapAttrs' (name: rs: lib.nameValuePair "nerdctl-${name}" (require true rs)) refs
      // {
        agent-config-migration = require false (
          map at [
            "/mnt/SSD/apps/openchamber/nix-root"
            "/mnt/SSD/agent-config"
          ]
        );
        postgresql-init = require false [ (at "/mnt/SSD/apps/postgresql/18") ];
      };
  };
}
