{ lib, containers }:
let
  inherit (import ./snapshot-policy.nix)
    mounts
    shared
    legacyCaches
    pending
    ;
  under = root: path: path == root || lib.hasPrefix (if root == "/" then root else "${root}/") path;
  parentFor =
    path:
    lib.last (
      lib.sort (a: b: builtins.stringLength a < builtins.stringLength b) (
        lib.filter (root: under root path) (builtins.attrNames mounts)
      )
    );
  dedicated =
    path: isCache:
    let
      parent = parentFor path;
      name = lib.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "${parent}/" path);
    in
    {
      inherit path parent isCache;
      dataset = "${mounts.${parent}}/${name}";
      existing = false;
    };
  named = lib.mapAttrs (
    _: spec:
    dedicated spec.path false
    // {
      dataset = spec.dataset or (dedicated spec.path false).dataset;
      existing =
        (mounts.${spec.path} or null) == (spec.dataset or null) && builtins.hasAttr spec.path mounts;
    }
  ) shared;
  volumes = lib.mapAttrs (
    _: c:
    c.volumes
    ++ lib.optional c.privateNixStore.enable {
      inherit (c.privateNixStore) hostPath isCache;
      sharedDataset = null;
    }
  ) containers;
  unmanaged =
    path:
    lib.any (root: under root path) [
      "/nix/store"
      "/run"
      "/etc/localtime"
    ];
  validPath =
    path:
    lib.hasPrefix "/" path
    && lib.all (
      part:
      !lib.elem part [
        ""
        "."
        ".."
      ]
    ) (lib.splitString "/" (lib.removePrefix "/" path));
  classify =
    v:
    if v.sharedDataset != null then
      named.${v.sharedDataset} or null
    else if unmanaged v.hostPath then
      null
    else
      dedicated v.hostPath v.isCache;
  refs = lib.mapAttrs (
    _: vs:
    lib.filter (r: r.spec != null) (
      map (v: {
        inherit (v) hostPath;
        spec = classify v;
      }) vs
    )
  ) volumes;
  entries =
    lib.concatMap (vs: map (r: r.spec) vs) (lib.attrValues refs)
    ++ map (path: dedicated path true) legacyCaches;
  unique = lib.unique entries;
  active = spec: !lib.elem spec.path pending;
in
{
  inherit
    active
    mounts
    refs
    unique
    ;
  assertions =
    lib.concatLists (
      lib.mapAttrsToList (
        name: vs:
        map (v: {
          assertion =
            validPath v.hostPath
            && (
              if v.sharedDataset != null then
                builtins.hasAttr v.sharedDataset named
                && under named.${v.sharedDataset}.path v.hostPath
                && !v.isCache
              else if unmanaged v.hostPath then
                !v.isCache
              else
                (parentFor v.hostPath) != "/" && !builtins.hasAttr v.hostPath mounts
            );
          message = "${name}: classify ${v.hostPath} as a dedicated data volume, a valid named shared dataset, or an unmanaged system mount.";
        }) vs
      ) volumes
    )
    ++ [
      {
        assertion = lib.all (p: lib.any (s: s.path == p && !s.existing) unique) pending;
        message = "serverone volume rollout contains a stale pending path.";
      }
      {
        assertion = lib.all (
          a:
          lib.all (
            b: a == b || (a.dataset != b.dataset && !(under a.path b.path) && !(under b.path a.path))
          ) unique
        ) unique;
        message = "serverone storage paths overlap, derive the same dataset name or disagree on cache status. Use one named shared dataset for overlapping bind mounts.";
      }
      {
        assertion = lib.all (
          spec:
          builtins.match "[a-zA-Z0-9_./:-]+" spec.dataset != null
          && (spec.existing || !(lib.elem spec.dataset (lib.attrValues mounts)))
        ) unique;
        message = "A managed volume has an invalid dataset name or collides with an existing host dataset.";
      }
    ];
}
