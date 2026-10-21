{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  name = "game-server-runner";
  baseDir = "/mnt/SSD/apps/${name}";
  worldDir = "/mnt/SSD/minecraft/Friends-Git";

  # One merged tree for the image root: the runner binary, restic and
  # the java the world in use runs on. Needed because nix-snapshotter's
  # copyToRoot merge cannot join the jdk tree raw — its top-level dirs
  # are themselves symlinks (bin -> lib/openjdk/bin) and collide with
  # the /bin another package creates (and symlinkJoin silently drops
  # them too). The real directory /lib/openjdk/bin survives the merge,
  # so the container PATH includes it for `command = "java"`; bump the
  # jdk here together with the world.
  imageRoot = pkgs.symlinkJoin {
    name = "game-server-runner-image";
    paths = [
      pkgs.game-server-runner
      pkgs.jdk21_headless
      pkgs.restic
    ];
  };
in
{
  # sops keys (in secrets-repo, serverone.yaml), rendered into the env and
  # config templates below:
  # - game-server-runner/oauth-client-id + /oauth-client-secret: the tsidp
  #   client registration (docs/deployments/tsidp-game-server-runner.md),
  #   OIDC admin login
  # - game-server-runner/telegram-token, -username, -chat-ids: the companion
  #   bot, login widget and notifications; an empty token turns telegram
  #   (login and notifications) off
  # - game-server-runner/restic-password: the restic backups read it from
  #   the inherited environment (same repo as the old mc-runner)
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    game-server-runner-oauth-client-id.key = "game-server-runner/oauth-client-id";
    game-server-runner-oauth-client-secret.key = "game-server-runner/oauth-client-secret";
    game-server-runner-telegram-token.key = "game-server-runner/telegram-token";
    game-server-runner-telegram-username.key = "game-server-runner/telegram-username";
    game-server-runner-telegram-chat-ids.key = "game-server-runner/telegram-chat-ids";
    game-server-runner-restic-password.key = "game-server-runner/restic-password";
  };

  # The app reads all four OIDC settings as a unit: the template renders
  # them together (ff-style) so a half-rendered secret file cannot turn
  # the admin login off or leave it half-wired (the app refuses to start).
  sops.templates."game-server-runner-env".content = lib.mkIf (options ? nerdctl-containers) (
    # sh
    ''
      OIDC_ISSUER=https://idp.internal.polpetta.online
      OIDC_CLIENT_ID=${config.sops.placeholder."game-server-runner-oauth-client-id"}
      OIDC_CLIENT_SECRET=${config.sops.placeholder."game-server-runner-oauth-client-secret"}
      ADMIN_USERNAME=jack
      RESTIC_PASSWORD=${config.sops.placeholder."game-server-runner-restic-password"}
    ''
  );

  # Global config (config.toml, the old config.yml). The telegram
  # placeholders are not secrets but this is part of the one sops edit
  # the deployment needs anyway, and it keeps token/username/chat ids
  # out of this repo; an empty token disables telegram login and
  # notifications. Unlike the env file (only nerdctl on the host ever
  # opens it) this file is bind-mounted into the container, so it must
  # be readable there: the rendered file gets the container uid's
  # ownership and group, like the frp/openchamber container files.
  sops.templates."game-server-runner-config" = lib.mkIf (options ? nerdctl-containers) {
    owner = "container-${toString config.nerdctl-containers.${name}.uid}";
    group = "containers";
    mode = "0400";
    restartUnits = [ "nerdctl-${name}.service" ];
    # toml
    content = ''
      db_path = "/game-server-runner/game-server-runner.db"
      port = 4479
      connect_url = "localhost:25565"
      server_dir = "/world"
      minutes_before_stop = 15

      restic_enable = true
      restic_path = "restic"
      restic_repo = "/backup"

      [telegram]
      token = "${config.sops.placeholder."game-server-runner-telegram-token"}"
      username = "${config.sops.placeholder."game-server-runner-telegram-username"}"
      chat_ids = "${config.sops.placeholder."game-server-runner-telegram-chat-ids"}"
    '';
  };

  sops.templates."game-server-runner-env".restartUnits = lib.mkIf (options ? nerdctl-containers) [
    "nerdctl-${name}.service"
  ];

  polpetta.services.${name} = {
    container = {
      id = 13;

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        name = "game-server-runner";
        tag = "nix-local";

        copyToRoot = [
          pkgs.dockerTools.caCertificates
          imageRoot
        ];

        config.entrypoint = [ "/bin/game-server-runner" ];
      };

      # CONFIG_PATH is the only env var the app reads itself; the rest
      # of its config now lives in config.toml (above). PATH carries the
      # jdk's merged interior bin so `command = "java"` resolves
      # (see imageRoot above).
      environment = {
        PATH = "/lib/openjdk/bin:/bin";
        CONFIG_PATH = "/game-server-runner/config.toml";
      };

      environmentFiles = [ config.sops.templates."game-server-runner-env".path ];

      ports = [
        "25565:25565/tcp"
        "19132:19132/udp"
        "19132:19132/tcp"
      ];

      volumes = [
        {
          hostPath = baseDir;
          containerPath = "/game-server-runner";
        }
        {
          hostPath = worldDir;
          containerPath = "/world";
        }
        {
          hostPath = config.sops.templates."game-server-runner-config".path;
          containerPath = "/game-server-runner/config.toml";
          readOnly = true;
        }
        {
          # The restic backup repo of the old mc-runner deployment; the
          # repo layout is compatible, old backup snapshots stay valid.
          hostPath = "/mnt/HDD/apps/mc-runner/Friends-Git";
          containerPath = "/backup";
        }
      ];
    };

    web = {
      port = 4479;
      access = "public";
      # Keep the historical domain: the service was renamed when the
      # mc-runner rewrite landed, but players' bookmarks (and the tsidp
      # client registration) keep pointing at mc-runner.polpetta.online.
      domain = "mc-runner.polpetta.online";
      nginx.extraConfig = ''
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
      '';
    };

    raw = [
      {
        port = 25565;
        access = "public";
        record = "mc";
      }
      {
        port = 19132;
        proto = "udp";
        access = "public";
      }
    ];
  };
}
