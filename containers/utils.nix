{
  givePermissions =
    {
      pkgs,
      containerName,
      sleepTime ? 5,
      adminOnlyDirs ? [ ],
      userDirs ? [ ],
    }:
    let
      setfacl = "${pkgs.acl}/bin/setfacl";
    in
    {
      systemd.services."podman-${containerName}".postStart =
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
              echo "Set permissions \"admin only\" for $f for container ${containerName}"
            '') adminOnlyDirs)
          ++ (map (
            x:
            # sh
            ''
              f="${x}"
              chown -R containers:containers $f
              ${setfacl} -R -m u:billy:rwx $f
              ${setfacl} -R -m d:u:billy:rwx $f
              echo "Set permissions \"user only\" for $f for container ${containerName}"
            '') userDirs)
        );
    };

  setCommonContainerConfig =
    {
      ip,
      dns ? "10.0.1.11",
      tmpfs ? [ ],
      autoUpdate ? true,
      runByUser ? true,
    }:
    {
      user = if runByUser then "5000:5000" else null;
      extraOptions = [
        "--ip=${ip}"
      ]
      ++ (if dns != null then [ "--dns=${dns}" ] else [ ])
      ++ (builtins.foldl' (x: y: x ++ y) [ ] (
        map (x: [
          "--tmpfs"
          x
        ]) tmpfs
      ));
    }
    // (
      if autoUpdate then
        {
          labels = {
            "io.containers.autoupdate" = "registry";
          };

        }
      else
        { }
    );
}
