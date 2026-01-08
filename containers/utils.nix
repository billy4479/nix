{ pkgs, config }:
let
  lib = pkgs.lib;
  images = import ./images.nix;
in
{
  makeContainer =
    {
      name,
      id,

      imageToPull ? null,
      imageToBuild ? null,

      labels ? { },
      extraOptions ? [ ],

      volumes ? [ ],

      dns ? "10.0.1.11",
      tmpfs ? [ "/tmp" ],

      runByUser ? true,
      environment ? { },
      environmentFiles ? [ ],
      ports ? [ ],
      cmd ? [ ],
      entrypoint ? null,
    }:
    assert (id >= 2 && id <= 255);
    assert (imageToBuild == null && imageToPull != null || imageToBuild != null && imageToPull == null);
    let
      ip = "10.0.1.${toString id}";
      uid = toString (5000 + id);
      gid = "5000";

      # Volume creation
      setfacl = lib.getExe' pkgs.acl "setfacl";

      volumeDirScript =
        {
          uid,
          gid,
          volumes,
        }:
        lib.strings.concatMapStringsSep "\n" (
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
              currentPerm=$(stat -c %u:%g "${v.hostPath}")
              if [ "$currentPerm" != "${uid}:${gid}" ]; then
                chown -R ${uid}:${gid} "${v.hostPath}"
                ${setfacl} -R -m d:g:${aclTarget}:rwX,g:${aclTarget}:rwX "${v.hostPath}"
              fi
            ''
        ) volumes;

      # Image Logic
      nixImage =
        if imageToBuild != null then
          imageToBuild
        else if imageToPull != null then
          let
            imageData = images."${imageToPull}";
            srcImage = pkgs.dockerTools.pullImage imageData;
          in
          pkgs.nix-snapshotter.buildImage {
            name = imageToPull;
            tag = imageData.finalImageTag;
            fromImage = srcImage;
            resolvedByNix = true;
          }
        else
          throw "makeSnapshotterContainer: Must provide either imageToPull or imageToBuild";

      # Flags Construction
      volumeFlags = map (
        v: "-v ${v.hostPath}:${v.containerPath}:${if v.readOnly or false then "ro" else "rw"}"
      ) volumes;

      tmpfsFlags = map (t: "--tmpfs ${t}") tmpfs;
      envFlags = lib.mapAttrsToList (n: v: "-e ${n}=\"${v}\"") (
        environment
        // {
          "TZ" = config.time.timeZone;
        }
      );
      envFileFlags = map (f: "--env-file \"${f}\"") environmentFiles;
      labelFlags = lib.mapAttrsToList (n: v: "-l ${n}=\"${v}\"") labels;
      portFlags = map (p: "-p ${p}") ports;
      userFlag = if runByUser then "--user ${uid}:${gid}" else "";
      cmdFlag = lib.strings.concatMapStringsSep " " (x: "\"${x}\"") cmd;

      allFlags = lib.flatten (
        [
          "--name ${name}"
          "--rm"
          "--log-driver=journald"
          "--net=nerdctl-bridge"
          "--ip=${ip}"
          volumeFlags
          tmpfsFlags
          envFlags
          envFileFlags
          labelFlags
          portFlags
          userFlag
          extraOptions
        ]
        ++ lib.optional (dns != null) "--dns=${dns}"
        ++ lib.optional (entrypoint != null) "--entrypoint \"${lib.concatStringsSep " " entrypoint}\""
        ++ [
          "nix:0${nixImage}"
          cmdFlag
        ]
      );
    in
    {
      systemd.services."nerdctl-${name}" = {
        after = [
          "volumes-${name}.service"
          "network-online.target"
        ];
        requires = [ "nerdctl-volumes-${name}.service" ];
        wantedBy = [ "multi-user.target" ];

        script = ''
          # Clean up previous state
          ${pkgs.nerdctl}/bin/nerdctl stop ${name} || true
          ${pkgs.nerdctl}/bin/nerdctl rm ${name} || true

          # Run the container
          exec ${pkgs.nerdctl}/bin/nerdctl run \
          ${lib.concatStringsSep " \\\n\t" allFlags}
        '';

        serviceConfig = {
          Restart = "always";
        };
      };

      systemd.services."nerdctl-volumes-${name}" = {
        script = volumeDirScript { inherit uid gid volumes; };
        before = [ "nerdctl-${name}.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
        };
      };
    };
}
