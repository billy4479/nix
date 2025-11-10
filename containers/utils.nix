{ pkgs, config }:
let
  lib = pkgs.lib;
  images = import ./images.nix;
  setfacl = "${pkgs.acl}/bin/setfacl";
  sleepTime = 5;
in
{
  makeContainer =
    {
      name,
      image,
      ip,

      imageFile ? null,
      labels ? { },
      extraOptions ? [ ],

      adminOnlyDirs ? [ ],
      userDirs ? [ ],

      dns ? "10.0.1.11",
      tmpfs ? [ "/tmp" ],

      autoUpdate ? true,
      runByUser ? true,
      ...
    }@args:
    {
      virtualisation.oci-containers.containers."${name}" =
        lib.recursiveUpdate
          {
            image = if imageFile != null then image else "${image}:${images."${image}".finalImageTag}";
            imageFile = if imageFile != null then imageFile else pkgs.dockerTools.pullImage (images."${image}");

            environment = {
              "TZ" = config.time.timeZone;
            };

            user = if runByUser then "5000:5000" else null;

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

            labels =
              (lib.optionalAttrs autoUpdate {
                "io.containers.autoupdate" = "registry";
              })
              // labels;
          }
          (
            builtins.removeAttrs args [
              "image"
              "imageFile"
              "name"
              "ip"
              "dns"
              "tmpfs"
              "adminOnlyDirs"
              "userDirs"
              "labels"
              "extraOptions"
              "runByUser"
              "autoUpdate"
            ]
          );

      systemd.services."podman-${name}".postStart =
        # sh
        ''
          sleep ${builtins.toString sleepTime}
        ''
        + pkgs.lib.concatStringsSep "\n" (
          (map (
            x:
            # sh
            ''
              f="${x}"
              chown -R containers:containers $f
              ${setfacl} -R -m g:admin:rwx $f
              ${setfacl} -R -m d:g:admin:rwx $f
              echo "Set permissions \"admin only\" for $f for container ${name}"
            '') adminOnlyDirs)
          ++ (map (
            x:
            # sh
            ''
              f="${x}"
              chown -R containers:containers $f
              ${setfacl} -R -m u:billy:rwx $f
              ${setfacl} -R -m d:u:billy:rwx $f
              echo "Set permissions \"user only\" for $f for container ${name}"
            '') userDirs)
        );
    };

}
