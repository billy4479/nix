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
              echo "Set permissions \"admin only\" for $f for ${containerName}"
            '') adminOnlyDirs)
          ++ (map (
            x:
            # sh
            ''
              f="${x}"
              chown -R containers:containers $f
              ${setfacl} -R -m u:billy:rwx $f
              ${setfacl} -R -m d:u:billy:rwx $f
              echo "Set permissions \"user only\" for $f for ${containerName}"
            '') userDirs)
        );
    };
}
