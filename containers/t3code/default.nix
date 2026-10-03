{
  config,
  flakeInputs,
  lib,
  pkgs,
  ...
}:
let
  name = "t3code";
  id = 24;
  # Shares the openchamber/syncthing UID so both control surfaces and
  # Syncthing can work on the same workspaces during the migration period.
  uid = 5021;
  uidString = toString uid;

  baseDir = "/mnt/SSD/apps/${name}";
  homeDir = "${baseDir}/home";
  # The workspaces stay owned by the openchamber container until it is
  # decommissioned; both containers run as the same UID.
  workspacesDir = "/mnt/SSD/apps/openchamber/workspaces";
  privateStoreRoot = "${baseDir}/nix-root";
  caCertificates = pkgs.dockerTools.caCertificates;

  artifacts = import ../../user/modules/applications/editor/opencode/artifacts.nix {
    inherit pkgs flakeInputs;
  };
  t3code = pkgs.t3code.override {
    opencode = artifacts.package;
  };

  # T3 Code identifies the container as `t3code-container` instead of the
  # ephemeral hostname assigned by nerdctl.
  fakeHostname = pkgs.writeShellScriptBin "hostname" # sh
    ''
      echo t3code-container
    '';

  runtime = pkgs.buildEnv {
    name = "t3code-container-runtime";
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
        claude-code
        codex
      ]
      ++ [
        t3code
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
    sandbox = true
    build-users-group =
    warn-dirty = false
    max-jobs = 2
    cores = 2
  '';

  identityFiles = pkgs.symlinkJoin {
    name = "t3code-container-identity";
    paths = [
      (pkgs.writeTextDir "/etc/passwd" ''
        root:x:0:0:root:/root:/bin/bash
        t3:x:${uidString}:5000:T3 Code agent:/home/t3:/bin/bash
        nobody:x:65534:65534:nobody:/nonexistent:/bin/sh
      '')
      (pkgs.writeTextDir "/etc/group" ''
        root:x:0:
        containers:x:5000:t3
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
      (pkgs.runCommand "t3code-container-fhs-links" { } ''
        mkdir -p "$out/usr/bin"
        ln -s /bin/env "$out/usr/bin/env"
      '')
    ];
  };

  setfacl = lib.getExe' pkgs.acl "setfacl";
  sshConfig = pkgs.writeText "t3code-ssh-config" ''
    Host github.com
      User git
      IdentityFile /home/t3/.ssh/id_ed25519
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
      IdentityFile /home/t3/.ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
  '';
in
{
  # The key is declared by the openchamber container while it is still
  # deployed; restart this container as well when it rotates.
  sops.secrets.openchamber-ssh-key.restartUnits = [ "nerdctl-t3code.service" ];

  nerdctl-containers.${name} = {
    inherit id;
    uid = 5021;
    useNginx = true;
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
        "/bin/t3"
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
    };

    cmd = [
      "serve"
      "--host"
      "0.0.0.0"
      "--port"
      "3000"
      "--no-browser"
    ];

    environment = {
      HOME = "/home/t3";
      USER = "t3";
      SHELL = "/bin/bash";
      PATH = "/bin";
      XDG_CACHE_HOME = "/home/t3/.cache";
      XDG_CONFIG_HOME = "/home/t3/.config";
      XDG_DATA_HOME = "/home/t3/.local/share";
      XDG_STATE_HOME = "/home/t3/.local/state";
      TMPDIR = "/tmp";
    };

    extraOptions = [
      "--read-only"
      "--pids-limit=2048"
    ];
    tmpfs = [ ];

    volumes = [
      {
        hostPath = homeDir;
        containerPath = "/home/t3";
        customPermissionScript = # sh
          ''
            ocHome="/mnt/SSD/apps/openchamber/home"

            mkdir -p \
              "${homeDir}/.cache" \
              "${homeDir}/.config" \
              "${homeDir}/.local/share" \
              "${homeDir}/.local/state" \
              "${homeDir}/.ssh"

            # Seed the non-declarative OpenCode state (configuration, skills,
            # authentication) from the openchamber container's home exactly
            # once; afterwards the two homes develop independently.
            if [ ! -e "${homeDir}/.config/opencode" ] && [ -d "$ocHome/.config/opencode" ]; then
              cp -a "$ocHome/.config/opencode" "${homeDir}/.config/opencode"
            fi
            if [ ! -e "${homeDir}/.local/share/opencode" ] && [ -d "$ocHome/.local/share/opencode" ]; then
              cp -a "$ocHome/.local/share/opencode" "${homeDir}/.local/share/opencode"
            fi
            if [ ! -e "${homeDir}/.agents" ] && [ -d "$ocHome/.agents" ]; then
              cp -a "$ocHome/.agents" "${homeDir}/.agents"
            fi

            chmod -R u+rwX "${homeDir}/.config"
            chown -R ${uidString}:5000 "${homeDir}"
            chmod 0700 "${homeDir}"
            chmod 0700 "${homeDir}/.ssh"

            ${setfacl} -R -m g:admin:rwX -m d:g:admin:rwX ${homeDir}
          '';
      }
      {
        hostPath = workspacesDir;
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
        containerPath = "/home/t3/.ssh/config";
        readOnly = true;
      }
      {
        hostPath = config.sops.secrets.openchamber-ssh-key.path;
        containerPath = "/home/t3/.ssh/id_ed25519";
        readOnly = true;
      }
    ];
  };
}
