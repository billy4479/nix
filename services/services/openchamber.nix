{
  config,
  flakeInputs,
  lib,
  options,
  pkgs,
  ...
}:
let
  name = "openchamber";
  id = 21;
  uid = 5000 + id;
  uidString = toString uid;

  baseDir = "/mnt/SSD/apps/${name}";
  workspaceDir = "${baseDir}/workspaces";
  privateStoreRoot = "${baseDir}/nix-root";
  caCertificates = pkgs.dockerTools.caCertificates;

  artifacts = import ../../user/modules/applications/editor/opencode/artifacts.nix {
    inherit pkgs flakeInputs;
  };
  openchamber = pkgs.openchamber-web.override {
    opencode = artifacts.package;
  };

  # OpenChamber identifies the container as `openchamber-container` instead of
  # the ephemeral hostname assigned by nerdctl.
  fakeHostname = pkgs.writeShellScriptBin "hostname" # sh
    ''
      echo openchamber-container
    '';

  runtime = pkgs.buildEnv {
    name = "openchamber-container-runtime";
    paths =
      with pkgs;
      [
        bashInteractive
        coreutils
        direnv
        less
        openssh
        nix
        git
        tini
      ]
      ++ [
        openchamber
        artifacts.package
      ];
    pathsToLink = [
      "/bin"
      "/share"
    ];
    postBuild = ''
      ln -sfn ${fakeHostname}/bin/hostname "$out/bin/hostname"
    '';
  };

  nixConfig = pkgs.writeTextDir "/etc/nix/nix.conf" ''
    experimental-features = nix-command flakes
    # Deliberately disabled: a working sandbox would require widening this
    # container's runtime policy (seccomp namespace syscalls plus unmasked
    # /proc and /sys). See AGENTS.md at the repository root.
    sandbox = false
    build-users-group =
    warn-dirty = false
  '';

  identityFiles = pkgs.symlinkJoin {
    name = "openchamber-container-identity";
    paths = [
      (pkgs.writeTextDir "/etc/passwd" ''
        root:x:0:0:root:/root:/bin/bash
        openchamber:x:${uidString}:5000:OpenChamber agent:/home/openchamber:/bin/bash
        nobody:x:65534:65534:nobody:/nonexistent:/bin/sh
      '')
      (pkgs.writeTextDir "/etc/group" ''
        root:x:0:
        containers:x:5000:openchamber
        nogroup:x:65534:
      '')
      # libgit2 does not support Git's safe.directory path globs, so trust all
      # repositories in this dedicated development container.
      (pkgs.writeTextDir "/etc/gitconfig" ''
        [safe]
          directory = *
      '')
      (pkgs.writeTextDir "/etc/ssh/ssh_known_hosts" ''
        github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
      '')
      (pkgs.runCommand "openchamber-container-fhs-links" { } ''
        mkdir -p "$out/usr/bin"
        ln -s /bin/env "$out/usr/bin/env"
      '')
    ];
  };

  setfacl = lib.getExe' pkgs.acl "setfacl";
  getfacl = lib.getExe' pkgs.acl "getfacl";
  sshConfig = pkgs.writeText "openchamber-ssh-config" ''
    Host github.com
      User git
      IdentityFile /home/openchamber/.ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking yes

    Host computerone
      HostName 100.64.0.5

    Host portatilo
      HostName 100.64.0.6

    Host serverone
      HostName 10.0.1.1

    Host vps-proxy
      HostName external.polpetta.online

    Host computerone portatilo serverone vps-proxy
      User billy
      IdentityFile /home/openchamber/.ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
  '';
in
{
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    openchamber-env.restartUnits = [ "nerdctl-openchamber.service" ];
    openchamber-ssh-key = {
      owner = "container-${uidString}";
      group = "containers";
      mode = "0400";
      restartUnits = [ "nerdctl-openchamber.service" ];
    };
  };

  polpetta.services.${name} = {
    container = {
      inherit id uid;
      workingDirectory = "/workspace";

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";

        copyToRoot = [
          runtime
          nixConfig
          identityFiles
          caCertificates
        ];

        config.entrypoint = [
          "/bin/tini"
          "--"
          "/bin/openchamber"
        ];
      };

      privateNixStore = {
        enable = true;
        hostPath = privateStoreRoot;
        seedPackages = [
          runtime
          artifacts.skills
          nixConfig
          identityFiles
          caCertificates
        ];
        # Agent sessions build nix closures into this store without ever GCing
        # them, and it reached 414 GiB against a pool with ~150 GiB free. The
        # limit is far above the seed closures' few GiB so ordinary builds
        # between restarts never trigger a wipe.
        wipeAboveGib = 100;
      };

      cmd = [
        "serve"
        "--foreground"
        "--host"
        "0.0.0.0"
        "--port"
        "3000"
      ];

      # OpenAI fixes this callback URI to localhost. Expose it only through an
      # SSH local forward to serverone rather than directly on the network.
      ports = [ "127.0.0.1:1455:1455/tcp" ];

      environment = {
        HOME = "/home/openchamber";
        USER = "openchamber";
        SHELL = "/bin/bash";
        PATH = "/bin";
        XDG_CACHE_HOME = "/home/openchamber/.cache";
        XDG_CONFIG_HOME = "/home/openchamber/.config";
        XDG_DATA_HOME = "/home/openchamber/.local/share";
        XDG_STATE_HOME = "/home/openchamber/.local/state";
        OPENCODE_BINARY = "/bin/opencode";
        TMPDIR = "/tmp";
      };
      environmentFiles = [ config.sops.secrets.openchamber-env.path ];

      extraOptions = [
        "--read-only"
        "--pids-limit=2048"
      ];
      memory = "8g";
      cpus = 4;
      tmpfs = [ ];
      # After a deploy, preStart copies the fresh runtime closure (GBs) into
      # the private store; the 90s systemd default timed out mid-copy. A start
      # that also wipes an over-limit store adds a multi-minute rm of millions
      # of files on top.
      startTimeout = 1800;

      volumes = [
        {
          hostPath = "${baseDir}/home";
          containerPath = "/home/openchamber";
          # The full recursive repair rewrites ~500k inodes and costs up to a
          # minute, which alone pushed starts past the unit's start timeout.
          # Probe first and only repair on real drift: the directory's default
          # ACL propagates g:admin to newly created files, and the ownership
          # scan exits at the first file owned by someone else (e.g. host-side
          # edits through the admin ACL). Only the "other" permission class is
          # pinned to zero: group bits legitimately vary with the ACL (mask,
          # setgid), so a fixed mode like 0700 never holds on an ACL'd dir.
          customPermissionScript =
            let
              permsAreGood = # sh
                ''
                  permsOk=1
                  [ "$(stat -c %u:%g "${baseDir}/home")" = "${uidString}:5000" ] || permsOk=0
                  [ "$(stat -c %a "${baseDir}/home" | tail -c 2)" = 0 ] || permsOk=0
                  [ "$(stat -c %a "${baseDir}/home/.ssh" | tail -c 2)" = 0 ] || permsOk=0
                  [ "$(${getfacl} -p "${baseDir}/home" 2>/dev/null | grep -c '^group:admin:')" -ge 1 ] || permsOk=0
                  [ "$(${getfacl} -p "${baseDir}/home" 2>/dev/null | grep -c '^default:group:admin:')" -ge 1 ] || permsOk=0
                  [ -z "$(find "${baseDir}/home" -xdev \
                    \( ! -user ${uidString} -o ! -group 5000 \) -print -quit 2>/dev/null)" ] || permsOk=0
                  [ "$permsOk" = 1 ]
                '';
            in
            # sh
            ''
              mkdir -p \
                "${baseDir}/home/.agents" \
                "${baseDir}/home/.cache" \
                "${baseDir}/home/.config/opencode" \
                "${baseDir}/home/.local/share" \
                "${baseDir}/home/.local/state" \
                "${baseDir}/home/.ssh"

              if ${permsAreGood}
              then
                echo "Permissions for ${baseDir}/home are good"
              else
                echo "Repairing permissions for ${baseDir}/home"
                chmod -R u+rwX "${baseDir}/home/.config/opencode"
                chown -R ${uidString}:5000 "${baseDir}/home"
                chmod 0700 "${baseDir}/home"
                chmod 0700 "${baseDir}/home/.ssh"

                ${setfacl} -R -m g:admin:rwX -m d:g:admin:rwX ${baseDir}/home
              fi
            '';
        }
        {
          hostPath = workspaceDir;
          containerPath = "/workspace";
        }
        {
          hostPath = "${baseDir}/tmp";
          containerPath = "/tmp";
          customPermissionScript = # sh
            ''
              chown ${uidString}:5000 "${baseDir}/tmp"
              chmod 0700 "${baseDir}/tmp"
            '';
        }
        {
          hostPath = "${sshConfig}";
          containerPath = "/home/openchamber/.ssh/config";
          readOnly = true;
        }
        {
          hostPath = config.sops.secrets.openchamber-ssh-key.path;
          containerPath = "/home/openchamber/.ssh/id_ed25519";
          readOnly = true;
        }
      ];
    };

    web = {
      port = 3000;
      access = "tailnet";
      # Chat UI attachments are arbitrary files, so allow generous bodies.
      nginx.extraConfig = ''
        client_max_body_size 256M;
      '';
    };
  };
}
