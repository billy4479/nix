{
  config,
  lib,
  pkgs,
  ...
}:
let
  images = import ./images.nix;

  makeContainer =
    name: cfg:
    assert (cfg.id >= 2 && cfg.id <= 255);
    let
      ip = "10.0.1.${toString cfg.id}";
      uidInt = 5000 + cfg.id;
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
              ${
                if v.customPermissionScript != null then
                  v.customPermissionScript
                else
                  # sh
                  ''
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
              }

            ''
        ) volumes;

      # Image Logic
      tag = "nix-local";
      imageName = "${name}:${tag}";
      nixImage =
        if cfg.imageToBuild != null then
          cfg.imageToBuild
        else if cfg.imageToPull != null then
          let
            imageData = images."${cfg.imageToPull}";
            srcImage = pkgs.dockerTools.pullImage imageData;
          in
          pkgs.nix-snapshotter.buildImage {
            inherit name tag;
            fromImage = srcImage;
          }
        else
          throw "mkContainerService: Must provide either imageToPull or imageToBuild";

      namespace = "default";
      address = "/run/containerd/containerd.sock";

      loadToContainerd = nixImage.copyToContainerd {
        inherit namespace address;
      };

      # Flags Construction
      volumeFlags = map (
        v: "-v \"${v.hostPath}:${v.containerPath}:${if v.readOnly or false then "ro" else "rw"}\""
      ) cfg.volumes;

      tmpfsFlags = map (t: "--tmpfs ${t}") cfg.tmpfs;
      envFlags = lib.mapAttrsToList (n: v: "-e ${n}=\"${v}\"") (
        cfg.environment
        // {
          "TZ" = config.time.timeZone;
        }
      );
      envFileFlags = map (f: "--env-file \"${f}\"") cfg.environmentFiles;
      labelFlags = lib.mapAttrsToList (n: v: "-l ${n}=\"${v}\"") cfg.labels;
      portFlags = map (p: "-p ${p}") cfg.ports;
      cmdFlag = lib.strings.concatMapStringsSep " " (x: "\"${x}\"") cfg.cmd;

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
          cfg.extraOptions
        ]
        ++ lib.optional cfg.runByUser "--user ${uid}:${gid}"
        ++ lib.optional (cfg.dns != null) "--dns=${cfg.dns}"
        ++ lib.optional (cfg.entrypoint != null) "--entrypoint \"${cfg.entrypoint}\""
        ++ [
          imageName
        ]
        ++ lib.optional (cmdFlag != "") cmdFlag
      );

      # Dependencies
      dependencies = map (x: "nerdctl-${x}.service") cfg.dependsOn;
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
        partOf = [ "all-containers.target" ];
        wantedBy = [ "all-containers.target" ];

        path = [ pkgs.iptables ];

        preStart =
          let
            volumeDirScriptApplied = volumeDirScript {
              inherit uid gid;
              volumes = cfg.volumes;
            };
          in
          # sh
          ''
            ${volumeDirScriptApplied}

            ${nerdctl} stop ${name} 2>/dev/null >/dev/null || true
            ${nerdctl} rm ${name} 2>/dev/null >/dev/null || true

            ${loadToContainerd}/bin/copy-to-containerd
          '';

        script = ''
          exec ${nerdctl} \
            ${lib.concatStringsSep " \\\n  " allFlags}
        '';

        postStop = # sh
          ''
            echo "Unloading image"
            ${nerdctl} --address ${address} --namespace ${namespace} rm -f ${name} 2>/dev/null >/dev/null || true
            ${nerdctl} --address ${address} --namespace ${namespace} rmi -f ${imageName} 2>/dev/null >/dev/null || true
          '';

        serviceConfig = {
          Restart = "always";
          Slice = "all-containers.slice";
        }
        // lib.optionalAttrs (cfg.stopTimeout != null) {
          TimeoutStopSec = cfg.stopTimeout;
        };
      };
    };
in
{
  options.nerdctl-containers = lib.mkOption {
    description = "Attribute set of nerdctl containers to create.";
    default = { };
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        {
          options = {
            id = lib.mkOption {
              type = lib.types.int;
              description = "Container ID (must be between 2 and 255). used for IP address and UID.";
            };

            imageToPull = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Image name key from images.nix to pull.";
            };

            imageToBuild = lib.mkOption {
              type = lib.types.nullOr lib.types.package;
              default = null;
              description = "Nix derivation of the image to build.";
            };

            labels = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Container labels.";
            };

            extraOptions = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Extra flags for nerdctl run.";
            };

            volumes = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    hostPath = lib.mkOption { type = lib.types.str; };
                    containerPath = lib.mkOption { type = lib.types.str; };
                    readOnly = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                    };
                    userAccessible = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                    };
                    customPermissionScript = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Custom shell script to set permissions. Replaces the default recursive chown behavior.";
                    };
                  };
                }
              );
              default = [ ];
              description = "List of volumes to mount.";
            };

            dns = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = "10.0.1.11";
              description = "DNS server for the container.";
            };

            tmpfs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "/tmp" ];
              description = "List of tmpfs mounts.";
            };

            runByUser = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to run as a user (uid=5000+id).";
            };

            environment = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Environment variables.";
            };

            environmentFiles = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Files containing environment variables.";
            };

            ports = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Port mappings.";
            };

            cmd = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Command to run in the container.";
            };

            entrypoint = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Entrypoint for the container.";
            };

            dependsOn = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Names of other containers that should be started before this one.";
            };

            stopTimeout = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "TimeoutStopSec for the systemd service.";
            };
          };
        }
      )
    );
  };

  config = lib.mkIf (config.nerdctl-containers != { }) (
    let
      containerConfigs = lib.mapAttrsToList makeContainer config.nerdctl-containers;
    in
    {
      users = lib.mkMerge (
        map (c: c.users) containerConfigs
        ++ [
          {
            groups.containers.gid = 5000;
          }
        ]
      );
      systemd = lib.mkMerge (
        map (c: c.systemd) containerConfigs
        ++ [
          {
            slices.all-containers = {
              description = "Slice for all nerdctl containers";
            };
            targets.all-containers = {
              wantedBy = [ "multi-user.target" ];
            };
          }
        ]
      );
    }
  );
}
