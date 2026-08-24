{
  config,
  flakeInputs,
  lib,
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

  runtime = pkgs.buildEnv {
    name = "openchamber-container-runtime";
    paths =
      with pkgs;
      [
        bashInteractive
        coreutils
        curl
        diffutils
        direnv
        fd
        file
        findutils
        gawk
        gh
        git
        gnugrep
        gnumake
        gnused
        gnutar
        gzip
        jq
        less
        nix
        openssh
        p7zip
        patch
        procps
        python3
        ripgrep
        util-linux
        which
        xz
        zstd
      ]
      ++ [
        openchamber
        artifacts.package
      ];
    pathsToLink = [
      "/bin"
      "/share"
    ];
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
  sops.secrets = {
    openchamber-env.restartUnits = [ "nerdctl-openchamber.service" ];
    openchamber-ssh-key = {
      owner = "container-${uidString}";
      group = "containers";
      mode = "0400";
      restartUnits = [ "nerdctl-openchamber.service" ];
    };
  };

  nerdctl-containers.${name} = {
    inherit id uid;
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

      config.entrypoint = [ "/bin/openchamber" ];
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
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
      "--pids-limit=2048"
    ];
    tmpfs = [ ];

    volumes = [
      {
        hostPath = "${baseDir}/home";
        containerPath = "/home/openchamber";
        customPermissionScript = # sh
          ''
            mkdir -p \
              "${baseDir}/home/.agents" \
              "${baseDir}/home/.cache" \
              "${baseDir}/home/.config/opencode" \
              "${baseDir}/home/.local/share" \
              "${baseDir}/home/.local/state" \
              "${baseDir}/home/.ssh"
            chmod -R u+rwX "${baseDir}/home/.config/opencode"
            chown -R ${uidString}:5000 "${baseDir}/home"
            chmod 0700 "${baseDir}/home"
            chmod 0700 "${baseDir}/home/.ssh"

            ${setfacl} -R -m g:admin:rwX -m d:g:admin:rwX ${baseDir}/home
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
}
