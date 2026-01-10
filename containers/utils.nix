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

      dependsOn ? [ ],
    }:
    assert (id >= 2 && id <= 255);
    let
      ip = "10.0.1.${toString id}";
      uidInt = 5000 + id;
      uid = toString uidInt;
      gid = "5000";

      nerdctl = lib.getExe pkgs.nerdctl;

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
              echo "Current permissions of ${v.hostPath}: $currentPerm"
              if [ "$currentPerm" != "${uid}:${gid}" ]; then
                echo "Changing permissions for ${v.hostPath}"
                chown -R ${uid}:${gid} "${v.hostPath}"
                ${setfacl} -R -m d:g:${aclTarget}:rwX,g:${aclTarget}:rwX "${v.hostPath}"
              else
                echo "Permissions for ${v.hostPath} are good"
              fi
            ''
        ) volumes;

      # Image Logic
      tag = "nix-local";
      imageName = "${name}:${tag}";
      nixImage =
        if imageToBuild != null then
          imageToBuild
        else if imageToPull != null then
          let
            imageData = images."${imageToPull}";
            srcImage = pkgs.dockerTools.pullImage imageData;
          in
          pkgs.nix-snapshotter.buildImage {
            inherit name tag;
            fromImage = srcImage;
          }
        else
          throw "makeSnapshotterContainer: Must provide either imageToPull or imageToBuild";

      namespace = "default";
      address = "/run/containerd/containerd.sock";

      loadToContainerd = nixImage.copyToContainerd {
        inherit namespace address;
      };

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
      cmdFlag = lib.strings.concatMapStringsSep " " (x: "\"${x}\"") cmd;

      allFlags = lib.flatten (
        [
          "--snapshotter nix"
          "--address ${address}"
          "--namespace ${namespace}"
          "run"
          "--name ${name}"
          "--rm"
          "--pull never"
          "--log-driver=journald"
          "--net=nerdctl-bridge"
          "--ip=${ip}"
          volumeFlags
          tmpfsFlags
          envFlags
          envFileFlags
          labelFlags
          portFlags
          extraOptions
        ]
        ++ lib.optional runByUser "--user ${uid}:${gid}"
        ++ lib.optional (dns != null) "--dns=${dns}"
        ++ lib.optional (entrypoint != null) "--entrypoint \"${entrypoint}\""
        ++ [
          imageName
        ]
        ++ lib.optional (cmdFlag != "") cmdFlag
      );

      # Dependencies
      dependencies = map (x: "nerdctl-${x}.service") dependsOn;
    in
    {
      users.users."container-${name}" = {
        isSystemUser = true;
        name = "container-${uid}";
        uid = uidInt;
        group = "containers";
        description = "User for container ${name}";
        createHome = false;
      };

      systemd.services."nerdctl-${name}" = {
        after = [
          "network-online.target"
          "containerd.service"
          "nix-snapshotter.service"
        ]
        ++ dependencies;

        requires = [
          "network-online.target"
          "containerd.service"
          "nix-snapshotter.service"
        ]
        ++ dependencies;
        wantedBy = [ "multi-user.target" ];

        path = [ pkgs.iptables ];

        preStart = # sh
          ''
            ${volumeDirScript { inherit uid gid volumes; }}

            ${nerdctl} stop ${name} 2>&1 >/dev/null || true
            ${nerdctl} rm ${name} 2>&1 >/dev/null || true

            ${loadToContainerd}/bin/copy-to-containerd
          '';

        script = ''
          exec ${nerdctl} \
              ${lib.concatStringsSep " \\\n\t" allFlags} \
              2>&1 >/dev/null 
        '';

        postStop = # sh
          ''
            echo "Unloading image"
            ${nerdctl} --address ${address} --namespace ${namespace} rm -f ${name} 2>&1 >/dev/null || true
            ${nerdctl} --address ${address} --namespace ${namespace} rmi -f ${imageName} 2>&1 >/dev/null || true
          '';

        serviceConfig = {
          Restart = "always";
        };
      };
    };
}
