{ pkgs, config }:
let
  lib = pkgs.lib;
  images = import ./images.nix;

  setfacl = lib.getExe' pkgs.acl "setfacl";

  # Helper to generate volume script (shared)
  mkVolumeDirHelper =
    { uid, gid }:
    v:
    let
      aclTarget = if v.userAccessible or false then "family" else "admin";
    in
    if v.readOnly or false then
      ""
    else
      ''
        mkdir -p "${v.hostPath}"
        currentPerm=$(stat -c %u:%g "${v.hostPath}")
        if [ "$currentPerm" != "${uid}:${gid}" ]; then
          chown -R ${uid}:${gid} "${v.hostPath}"
          ${setfacl} -R -m d:g:${aclTarget}:rwX,g:${aclTarget}:rwX "${v.hostPath}"
        fi
      '';

in
{
  makeContainer =
    {
      name,
      image,
      id,

      imageFile ? null,
      extraOptions ? [ ],

      volumes ? [ ],

      dns ? "10.0.1.11",
      tmpfs ? [ "/tmp" ],

      runByUser ? true,
      environment ? { },
      ports ? [ ],
      cmd ? [ ],
      entrypoint ? null,
    }:
    assert (id >= 2 && id <= 255);
    let
      ip = "10.0.1.${toString id}";
      uid = toString (5000 + id);
      gid = "5000";

      mkVolumeFlag = v: "${v.hostPath}:${v.containerPath}:${if v.readOnly or false then "ro" else "rw"}";
      mkVolumeDir = mkVolumeDirHelper { inherit uid gid; };

      createVolumeDirScript = lib.strings.concatMapStringsSep "\n" mkVolumeDir volumes;
      volumeFlag = map mkVolumeFlag volumes;
    in
    {
      virtualisation.oci-containers.containers."${name}" = {
        image = if imageFile != null then image else "${image}:${images."${image}".finalImageTag}";
        imageFile = if imageFile != null then imageFile else pkgs.dockerTools.pullImage (images."${image}");

        environment = environment // {
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

        inherit cmd entrypoint ports;
      };

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

  makeSnapshotterContainer =
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

      autoUpdate ? true,
      runByUser ? true,
      environment ? { },
      ports ? [ ],
      cmd ? [ ],
      entrypoint ? null,
    }:
    assert (id >= 2 && id <= 255);
    let
      # Use new subnet 10.0.2.x for nerdctl
      ip = "10.0.2.${toString id}";
      uid = toString (5000 + id);
      gid = "5000";

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
      mkVolumeFlag =
        v: "-v ${v.hostPath}:${v.containerPath}:${if v.readOnly or false then "ro" else "rw"}";
      volumeFlags = map mkVolumeFlag volumes;

      mkVolumeDir = mkVolumeDirHelper { inherit uid gid; };
      createVolumeDirScript = lib.strings.concatMapStringsSep "\n" mkVolumeDir volumes;

      mkTmpfsFlag = t: "--tmpfs ${t}";
      tmpfsFlags = map mkTmpfsFlag tmpfs;

      # Env: Merge TZ with provided environment
      envMap = environment // {
        "TZ" = config.time.timeZone;
      };
      mkEnvFlag = n: v: "-e ${n}=\"${v}\"";
      envFlags = lib.mapAttrsToList mkEnvFlag envMap;

      # Labels
      mkLabelFlag = n: v: "-l ${n}=\"${v}\"";
      labelFlags = lib.mapAttrsToList mkLabelFlag labels;

      # Ports
      mkPortFlag = p: "-p ${p}";
      portFlags = map mkPortFlag ports;

      userFlag = if runByUser then "--user ${uid}:${gid}" else "";

      # Command
      entrypointFlag =
        if entrypoint != null then "--entrypoint ${lib.concatStringsSep " " entrypoint}" else "";

    in
    {
      systemd.services."nerdctl-${name}" = {
        after = [
          "volumes-${name}.service"
          "network-online.target"
        ];
        requires = [ "volumes-${name}.service" ];
        wantedBy = [ "multi-user.target" ];

        script = ''
          # Clean up previous state to mimic --replace
          ${pkgs.nerdctl}/bin/nerdctl stop ${name} || true
          ${pkgs.nerdctl}/bin/nerdctl rm ${name} || true
          rm -f /run/${name}.cid

          # Run the container
          exec ${pkgs.nerdctl}/bin/nerdctl run \
            --name ${name} \
            --rm \
            --log-driver=journald \
            --cidfile=/run/${name}.cid \
            --cgroup-manager=systemd \
            --net=nerdctl-bridge \
            --ip=${ip} \
            ${if dns != null then "--dns=${dns}" else ""} \
            ${builtins.concatStringsSep " " volumeFlags} \
            ${builtins.concatStringsSep " " tmpfsFlags} \
            ${builtins.concatStringsSep " " envFlags} \
            ${builtins.concatStringsSep " " labelFlags} \
            ${builtins.concatStringsSep " " portFlags} \
            ${userFlag} \
            ${entrypointFlag} \
            ${builtins.concatStringsSep " " extraOptions} \
            nix:0${nixImage} \
            ${builtins.concatStringsSep " " cmd}
        '';

        serviceConfig = {
          Restart = "always";
        };
      };

      systemd.services."volumes-${name}" = {
        script = createVolumeDirScript;
        before = [ "nerdctl-${name}.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
        };
      };
    };
}
