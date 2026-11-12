{
  config,
  domain,
  flakeInputs,
  lib,
  options,
  pkgs,
  ...
}:
let
  name = "t3code";
  id = 27;
  uid = 5021;
  baseDir = "/mnt/SSD/apps/t3code";
  home = "/home/t3";
  extensions = import ../pi/extensions { inherit pkgs; };
  development = import ../agent-runtime/development.nix { inherit pkgs flakeInputs; };
  direnv = import ../pi/direnv.nix { inherit pkgs; };
  entrypoint =
    pkgs.writeShellScript "t3code-entrypoint" # sh
      ''
        set -eu
        test -f /agent-config/AGENTS.md
        test -d /agent-config/skills
        mkdir -p /tmp/opencode
        ${pkgs.python3}/bin/python3 ${../pi/setup.py} --home "$HOME" --extensions ${extensions}
        exec /bin/t3 "$@"
      '';
  runtime = pkgs.buildEnv {
    name = "t3code-container-runtime";
    paths =
      (with pkgs; [
        bashInteractive
        # procps and util-linux also provide kill/uptime. Resolve those
        # deliberately instead of allowing arbitrary buildEnv collisions.
        (lib.hiPrio coreutils)
        less
        openssh
        nix
        nh
        git
        t3code
        pi-coding-agent
        # pi-free-provider's Zen transport starts a local Bun relay.
        bun
      ])
      ++ [
        direnv
        (import ../mail-watch { inherit pkgs; })
        development.chromium
        development.agentBrowser
        development.nvimFmt
        (pkgs.writeShellScriptBin "hostname" # sh
          ''
            echo t3code-container
          ''
        )
      ]
      ++ import ../agent-runtime/tools.nix { inherit pkgs; };
    pathsToLink = [
      "/bin"
      "/share"
    ];
  };
  sshConfig = pkgs.writeText "t3code-ssh-config" ''
    Host github.com
      User git
      IdentityFile ${home}/.ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking yes
    Host computerone
      HostName 100.64.0.5
    Host portatilo
      HostName 100.64.0.6
    Host serverone
      HostName 10.0.1.1
    Host vps-proxy
      HostName external.${domain}
    Host computerone portatilo serverone vps-proxy
      User billy
      IdentityFile ${home}/.ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
  '';
  files = pkgs.symlinkJoin {
    name = "t3code-container-config";
    paths = [
      (pkgs.writeTextDir "/etc/nix/nix.conf" ''
        experimental-features = nix-command flakes
        sandbox = false
        build-users-group =
        warn-dirty = false
      '')
      (pkgs.writeTextDir "/etc/gitconfig" ''
        [safe]
          directory = *
      '')
      (pkgs.writeTextDir "/etc/ssh/ssh_known_hosts" ''
        github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
      '')
      (pkgs.writeTextDir "/etc/bashrc" # sh
        ''
          if [[ $- == *i* ]]; then
            # direnv's generated hook embeds its own store executable. Route
            # every prompt through the scoped wrapper, not just hook creation.
            eval "$(${pkgs.direnv}/bin/direnv hook bash | ${pkgs.gnused}/bin/sed 's#${pkgs.direnv}/bin/direnv#/bin/direnv#g')"
          fi
        ''
      )
      (pkgs.writeTextDir "/etc/profile" # sh
        ''
          if [ -n "''${BASH_VERSION:-}" ]; then . /etc/bashrc; fi
        ''
      )
      (pkgs.runCommand "t3code-fhs-links" { } # sh
        ''
          mkdir -p "$out/usr/bin" "$out/etc"
          ln -s /bin/env "$out/usr/bin/env"
          ln -s /etc/bashrc "$out/etc/bash.bashrc"
        ''
      )
    ];
  };
in
{
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    openchamber-ssh-key.restartUnits = [ "nerdctl-t3code.service" ];
    mail-watch-google-client-id.key = "google-api/client-id";
    mail-watch-google-client-secret.key = "google-api/client-secret";
    mail-watch-telegram-token = {
      key = "telegram-bot/token";
      owner = "container-${toString uid}";
      group = "containers";
      mode = "0400";
      restartUnits = [ "nerdctl-t3code.service" ];
    };
    mail-watch-telegram-chat-id = {
      key = "telegram-bot/chat-id";
      owner = "container-${toString uid}";
      group = "containers";
      mode = "0400";
      restartUnits = [ "nerdctl-t3code.service" ];
    };
  };

  sops.templates.mail-watch-google-client = lib.mkIf (options ? nerdctl-containers) {
    owner = "container-${toString uid}";
    group = "containers";
    mode = "0400";
    restartUnits = [ "nerdctl-t3code.service" ];
    content = builtins.toJSON {
      installed = {
        client_id = config.sops.placeholder.mail-watch-google-client-id;
        client_secret = config.sops.placeholder.mail-watch-google-client-secret;
      };
    };
  };

  polpetta.services.t3code = {
    container = {
      inherit id uid;
      workingDirectory = "/workspace";
      copyToRoot = [
        runtime
        files
      ];
      entrypoint = [ entrypoint ];
      privateNixStore = {
        enable = true;
        hostPath = "${baseDir}/nix-root";
        seedPackages = [
          runtime
          files
          extensions
          entrypoint
        ];
      };
      cmd = [
        "serve"
        "--host"
        "0.0.0.0"
        "--port"
        "3000"
        "--base-dir"
        "${home}/.t3"
      ];
      environment = {
        HOME = home;
        USER = "t3";
        SHELL = "/bin/bash";
        PATH = "/bin";
        XDG_CACHE_HOME = "${home}/.cache";
        XDG_CONFIG_HOME = "${home}/.config";
        XDG_DATA_HOME = "${home}/.local/share";
        XDG_STATE_HOME = "${home}/.local/state";
        PI_CODING_AGENT_DIR = "${home}/.pi/agent";
        AGENTUP_URL = "https://agent-up.internal.${domain}";
        SEARXNG_BASE_URL = "https://searxng.internal.${domain}";
        SEARXNG_SAFE_SEARCH = "0";
        TMPDIR = "/tmp";
      };
      extraOptions = [
        "--read-only"
        "--pids-limit=2048"
      ];
      memory = "8g";
      cpus = 4;
      tmpfs = [ ];
      startTimeout = 1800;
      volumes = [
        {
          hostPath = "${baseDir}/home";
          containerPath = home;
          customPermissionScript = # sh
            ''
              mkdir -p "${baseDir}/home/.ssh"
              chown 5021:5000 "${baseDir}/home" "${baseDir}/home/.ssh"
              chmod 0700 "${baseDir}/home" "${baseDir}/home/.ssh"
              ${pkgs.acl}/bin/setfacl -m g:admin:rwx,d:g:admin:rwx "${baseDir}/home"
            '';
        }
        {
          hostPath = "/mnt/SSD/apps/openchamber/workspaces";
          containerPath = "/workspace";
        }
        {
          hostPath = "/mnt/SSD/agent-config";
          containerPath = "/agent-config";
          customPermissionScript = ":";
        }
        {
          hostPath = "${baseDir}/tmp";
          containerPath = "/tmp";
          customPermissionScript = # sh
            ''
              chown 5021:5000 "${baseDir}/tmp"
              chmod 0700 "${baseDir}/tmp"
            '';
        }
        {
          hostPath = development.agentBrowserSkill;
          containerPath = "${home}/.agents/skills/agent-browser";
          readOnly = true;
        }
        {
          hostPath = "${sshConfig}";
          containerPath = "${home}/.ssh/config";
          readOnly = true;
        }
        {
          hostPath = config.sops.templates.mail-watch-google-client.path;
          containerPath = "/run/secrets/mail-watch-google-client.json";
          readOnly = true;
        }
        {
          hostPath = config.sops.secrets.mail-watch-telegram-token.path;
          containerPath = "/run/secrets/telegram-bot-token";
          readOnly = true;
        }
        {
          hostPath = config.sops.secrets.mail-watch-telegram-chat-id.path;
          containerPath = "/run/secrets/telegram-bot-chat-id";
          readOnly = true;
        }
        {
          hostPath = config.sops.secrets.openchamber-ssh-key.path;
          containerPath = "${home}/.ssh/id_ed25519";
          readOnly = true;
        }
      ];
    };
    web = {
      port = 3000;
      access = "tailnet";
      probe.path = "/.well-known/t3/environment";
      nginx.extraConfig = ''
        client_max_body_size 256M;
      '';
    };
  };
  systemd.services.t3code-nix-gc = lib.mkIf (options ? nerdctl-containers) {
    description = "Prune stale T3 Code GC roots and collect build results";
    after = [ "nerdctl-t3code.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecCondition = "${pkgs.systemd}/bin/systemctl is-active --quiet nerdctl-t3code.service";
      ExecStart = "${lib.getExe pkgs.nerdctl} exec t3code /bin/nh clean user --elevation-strategy none --keep 5 --keep-since 7d --keep-one --max 107374182400";
      TimeoutStartSec = "30min";
    };
  };
  systemd.timers.t3code-nix-gc = lib.mkIf (options ? nerdctl-containers) {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
  };
}
