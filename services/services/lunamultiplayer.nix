{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  name = "lunamultiplayer";
  baseDir = "/mnt/SSD/apps/${name}";

  serverToml =
    pkgs.writeText "lunamultiplayer-server-toml" # toml
      ''
        server_name = "lunamultiplayer"
        command = "Server"

        # Luna logs join/leave events as (no lookarounds in the regex crate):
        #   [21:43:10][LMP]: Client <name> (<unique-id>) handshake successful, ...
        #   [21:44:00][Debug]: <name> sent Connection end message, reason: ...
        # The error path instead logs "Client <name> disconnected in ...";
        # it is not tracked (a duplicate capture group name is not allowed
        # in one pattern) and a failed handshake is not a player.
        join_regex = 'Client (?P<player>.+?) \((.+)\) handshake successful'
        leave_regex = '(?P<player>.+?) sent Connection end message'

        # SIGINT is Luna's documented clean stop ("quit by using Control+C
        # so a backup is properly made"); it saves the universe + backup on
        # the way out, so give it a generous grace before the SIGKILL. The
        # container stopTimeout must stay above it.
        [stop]
        mode = "signal"
        payload = "SIGINT"
        grace_period = "30s"
      '';
in
{
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    lunamultiplayer-oauth-client-id.key = "lunamultiplayer/oauth-client-id";
    lunamultiplayer-oauth-client-secret.key = "lunamultiplayer/oauth-client-secret";
    lunamultiplayer-telegram-token.key = "lunamultiplayer/telegram-token";
    lunamultiplayer-telegram-username.key = "lunamultiplayer/telegram-username";
    lunamultiplayer-telegram-chat-ids.key = "lunamultiplayer/telegram-chat-ids";
  };

  sops.templates."lunamultiplayer-env".content = lib.mkIf (options ? nerdctl-containers) (
    # sh
    ''
      OIDC_ISSUER=https://idp.internal.polpetta.online
      OIDC_CLIENT_ID=${config.sops.placeholder."lunamultiplayer-oauth-client-id"}
      OIDC_CLIENT_SECRET=${config.sops.placeholder."lunamultiplayer-oauth-client-secret"}
      ADMIN_USERNAME=jack
    ''
  );

  sops.templates."lunamultiplayer-env".restartUnits = lib.mkIf (options ? nerdctl-containers) [
    "nerdctl-${name}.service"
  ];

  sops.templates."lunamultiplayer-config" = lib.mkIf (options ? nerdctl-containers) {
    owner = "container-${toString config.nerdctl-containers.${name}.uid}";
    group = "containers";
    mode = "0400";
    restartUnits = [ "nerdctl-${name}.service" ];
    content =
      # toml
      ''
        db_path = "/data/game-server-runner.db"
        port = 4479
        connect_url = "lunamultiplayer.polpetta.online:8800"
        server_dir = "/data"
        minutes_before_stop = 15

        restic_enable = false

        [telegram]
        token = "${config.sops.placeholder."lunamultiplayer-telegram-token"}"
        username = "${config.sops.placeholder."lunamultiplayer-telegram-username"}"
        chat_ids = "${config.sops.placeholder."lunamultiplayer-telegram-chat-ids"}"
      '';
  };

  polpetta.services.${name} = {
    container = {
      id = 20;

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";

        copyToRoot = with pkgs; [
          dockerTools.caCertificates
          game-server-runner
          lunamultiplayer-server
        ];

        config.entrypoint = [ "/bin/game-server-runner" ];
      };

      environment = {
        CONFIG_PATH = "/game-server-runner/config.toml";
        LUNAMULTIPLAYER_DIR = "/data";
      };

      environmentFiles = [ config.sops.templates."lunamultiplayer-env".path ];

      # The runner stops the server gracefully on its own SIGTERM honoring server.toml's 30s
      # grace, so the container timeout must stay above it.
      stopTimeout = 45;

      volumes = [
        {
          hostPath = baseDir;
          containerPath = "/data";
        }
        {
          hostPath = "${serverToml}";
          containerPath = "/data/server.toml";
          readOnly = true;
        }
        {
          hostPath = config.sops.templates."lunamultiplayer-config".path;
          containerPath = "/game-server-runner/config.toml";
          readOnly = true;
        }
      ];
    };

    web = {
      port = 4479;
      access = "public";
      nginx.extraConfig = ''
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
      '';
    };

    raw = [
      {
        port = 8800;
        proto = "udp";
        access = "public";
      }
    ];
  };
}
