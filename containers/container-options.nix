{ lib }:
lib.types.submodule (
  { name, config, ... }:
  {
    options = {
      id = lib.mkOption {
        type = lib.types.int;
        description = "Container ID (must be between 2 and 255), used for its IP address.";
      };

      uid = lib.mkOption {
        type = lib.types.int;
        default = 5000 + config.id;
        defaultText = lib.literalExpression "5000 + config.id";
        description = "UID used to run the container and own its writable volumes.";
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

      useNginx = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this container is served through the nginx reverse proxy.";
      };

      extraOptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra flags for nerdctl run.";
      };

      capabilities = lib.mkOption {
        type = lib.types.listOf (lib.types.strMatching "CAP_[A-Z0-9_]+");
        default = [ ];
        description = "Linux capabilities to add after dropping the default capability set.";
      };

      memory = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Hard memory limit for the container, passed to nerdctl
          `--memory` (e.g. "8g"). Processes exceeding it are OOM killed.
          tmpfs mounts count towards this limit.
        '';
      };

      cpus = lib.mkOption {
        type = lib.types.nullOr (lib.types.either lib.types.int lib.types.float);
        default = null;
        description = ''
          Number of CPUs the container may use, passed to nerdctl
          `--cpus` (e.g. 4 or 1.5).
        '';
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
        default = [ "/tmp:size=128m" ];
        description = ''
          List of tmpfs mounts. tmpfs lives in RAM and counts towards the
          container's memory usage, so /tmp is capped by default: several
          applications (jackett's updater, byparr's solve artifacts) never
          clean up their own temporary files. Raise it per-container when
          an application legitimately needs more.
        '';
      };

      runByUser = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to run the container with its configured UID and the containers GID.";
      };

      noNewPrivileges = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to prevent the container processes from gaining privileges through exec.";
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

      workingDirectory = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Working directory for the container process.";
      };

      privateNixStore = lib.mkOption {
        description = "Private Nix store mounted at /nix inside the container.";
        default = { };
        type = lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "a private Nix store for this container";
            hostPath = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Host directory containing the private Nix root.";
            };
            seedPackages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
              description = "Packages copied into and rooted in the private store before startup.";
            };
            wipeAboveGib = lib.mkOption {
              type = lib.types.nullOr lib.types.ints.positive;
              default = null;
              description = ''
                Wipe the whole private store before startup when it exceeds this
                many GiB. Safe because the store is fully re-seeded from
                seedPackages right afterwards, but the limit must stay well
                above the seed closures' size or the store is rebuilt on every
                restart.
              '';
            };
          };
        };
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
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Seconds before nerdctl sends kill to container.";
      };

      startTimeout = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          Seconds before the unit's start job (preStart included) times out;
          null keeps systemd's 90s default. Raise it when preStart
          legitimately moves large amounts of data, e.g. seeding a private
          Nix store after a deploy.
        '';
      };

      extraPreStart = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Extra shell lines appended to the unit's preStart, after the
          image is loaded and before the container starts (runs as root on
          the host).
        '';
      };
    };
  }
)
