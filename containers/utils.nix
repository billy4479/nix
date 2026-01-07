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
      uid = toString (5000 + id);
      gid = "5000";

      setfacl = lib.getExe' pkgs.acl "setfacl";

      # Helper to convert volume object to OCI string
      mkVolumeFlag = v: "${v.hostPath}:${v.containerPath}:${if v.readOnly or false then "ro" else "rw"}";

      mkVolumeDir =
        v:
        let
          aclTarget = if v.userAccessible or false then "family" else "admin";
        in
        if v.readOnly or false then
          ""
        else
          # sh
          ''
            mkdir -p "${v.hostPath}"

            # We set these just once
            currentPerm=$(stat -c %u:%g "${v.hostPath}")
            if [ "$currentPerm" != "${uid}:${gid}" ]; then
              chown -R ${uid}:${gid} "${v.hostPath}"
              ${setfacl} -R -m d:g:${aclTarget}:rwX,g:${aclTarget}:rwX "${v.hostPath}"
            fi
          '';

      createVolumeDirScript = lib.strings.concatMapStringsSep "\n" mkVolumeDir volumes;
      volumeFlag = map mkVolumeFlag volumes;
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

            user = if runByUser then "${uid}:${gid}" else null;

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

            volumes = volumeFlag;

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

      systemd.services = {
        "podman-${name}" = {
          after = [ "volumes-${name}.service" ];
          requires = [ "volumes-${name}.service" ];
        };

        "volumes-${name}" = {
          script = createVolumeDirScript;
          before = [ "podman-${name}.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "root";
          };
        };
      };
    };

}
