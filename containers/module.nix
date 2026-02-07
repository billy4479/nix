{
  config,
  lib,
  pkgs,
  ...
}:
let
  utils = import ./utils.nix { inherit pkgs config; };
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
          };
        }
      )
    );
  };

  config = lib.mkIf (config.nerdctl-containers != { }) (
    let
      containerConfigs = lib.mapAttrsToList (
        name: cfg:
        utils.makeContainer {
          inherit name;
          inherit (cfg)
            id
            imageToPull
            imageToBuild
            labels
            extraOptions
            volumes
            dns
            tmpfs
            runByUser
            environment
            environmentFiles
            ports
            cmd
            entrypoint
            dependsOn
            ;
        }
      ) config.nerdctl-containers;
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
