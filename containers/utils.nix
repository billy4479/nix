{ pkgs, config }:
let
  lib = pkgs.lib;
  images = import ./images.nix;
in
{
  makeContainer =
    {
      name,
      image,
      id,

      imageFile ? null,
      labels ? { },
      extraOptions ? [ ],

      volumes ? [ ],

      dns ? "10.0.1.11",
      tmpfs ? [ "/tmp" ],

      autoUpdate ? true,
      runByUser ? true,
      ...
    }@args:
    assert (id >= 2 && id <= 255);
    let
      ip = "10.0.1.${toString id}";

      # Helper to convert volume object to OCI string
      mkOciVolume = v: "${v.hostPath}:${v.containerPath}:${if v.readOnly or false then "ro" else "rw"}";

      # Helper to create tmpfiles rules
      mkTmpRules =
        v:
        if v.readOnly or false then
          [ ]
        else
          let
            # Base rule to create directory with owner containers:containers
            createRule = "d \"${v.hostPath}\" 0770 containers containers - -";

            # ACL rule
            # userAccessible -> family (group)
            # !userAccessible -> admin (group)
            aclTarget = if v.userAccessible or false then "g:family:rwx" else "g:admin:rwx";

            # We need recursive ACLs (default and regular)
            aclEntry = "${aclTarget},d:${aclTarget}";

            aclRule = "A+ \"${v.hostPath}\" - - - - ${aclEntry}";
          in
          [
            createRule
            aclRule
          ];

      ociVolumes = map mkOciVolume volumes;
      tmpRules = lib.flatten (map mkTmpRules volumes);
    in
    {
      virtualisation.oci-containers.containers."${name}" =
        lib.recursiveUpdate
          {
            image = if imageFile != null then image else "${image}:${images."${image}".finalImageTag}";
            imageFile = if imageFile != null then imageFile else pkgs.dockerTools.pullImage (images."${image}");

            environment = {
              "TZ" = config.time.timeZone;
            };

            user = if runByUser then "${toString (5000 + id)}:5000" else null;

            extraOptions = [
              "--ip=${ip}"
            ]
            ++ (lib.optionals (dns != null) [ "--dns=${dns}" ])
            ++ (builtins.foldl' (x: y: x ++ y) [ ] (
              map (x: [
                "--tmpfs"
                x
              ]) tmpfs
            ))
            ++ extraOptions;

            volumes = ociVolumes;

            labels =
              (lib.optionalAttrs autoUpdate {
                "io.containers.autoupdate" = "registry";
              })
              // labels;
          }
          (
            removeAttrs args [
              "image"
              "imageFile"
              "name"
              "id"
              "dns"
              "tmpfs"
              "volumes"
              "labels"
              "extraOptions"
              "runByUser"
              "autoUpdate"
            ]
          );

      systemd.tmpfiles.rules = tmpRules;
    };

}
