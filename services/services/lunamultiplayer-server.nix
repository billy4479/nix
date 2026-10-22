{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  name = "lunamultiplayer-server";
  baseDir = "/mnt/SSD/apps/${name}";

  # One merged tree for the image root: the runner binary plus Luna's
  # Server. The runner spawns the game server it manages, so both live on
  # one image (same shape as the minecraft game-server-runner image).
  imageRoot = pkgs.symlinkJoin {
    name = "lunamultiplayer-server-image";
    paths = [
      pkgs.game-server-runner
      pkgs.lunamultiplayer-server
    ];
  };

  # server.toml holds no secrets, so it is rendered straight into the
  # store and bind-mounted into the server directory the runner reads it
  # from (game-server-runner expects it directly inside server_dir).
  serverToml = pkgs.writeText "lunamultiplayer-server-server-toml" # toml
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
  # sops keys (in secrets-repo, serverone.yaml), rendered into the env and
  # config templates below:
  # - lunamultiplayer-server/oauth-client-id + /oauth-client-secret: the
  #   tsidp client registration (docs/deployments/tsidp-game-server-runner.md),
  #   separate from the minecraft runner's because the redirect URI differs
  # - telegram token/username/chat ids are shared with the minecraft
  #   runner (same bot, sops keys declared in services/game-server-runner/):
  #   the login widget verifies payloads with the token and notifications
  #   land in the same admin chat. The approval queue and accounts are
  #   per-instance (a friend approved on the minecraft runner is unknown
  #   here until approved once)
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    lunamultiplayer-server-oauth-client-id.key = "lunamultiplayer-server/oauth-client-id";
    lunamultiplayer-server-oauth-client-secret.key = "lunamultiplayer-server/oauth-client-secret";
  };

  # The app reads the four OIDC settings as a unit: the template renders
  # them together (ff-style, fail closed like the minecraft runner).
  sops.templates."lunamultiplayer-server-env".content = lib.mkIf (options ? nerdctl-containers) (
    # sh
    ''
      OIDC_ISSUER=https://idp.internal.polpetta.online
      OIDC_CLIENT_ID=${config.sops.placeholder."lunamultiplayer-server-oauth-client-id"}
      OIDC_CLIENT_SECRET=${config.sops.placeholder."lunamultiplayer-server-oauth-client-secret"}
      ADMIN_USERNAME=jack
    ''
  );

  sops.templates."lunamultiplayer-server-env".restartUnits = lib.mkIf (options ? nerdctl-containers) [
    "nerdctl-${name}.service"
  ];

  # Global config (config.toml). The telegram placeholders are shared
  # secrets, so this file is a sops template like the minecraft runner's:
  # bind-mounted into the container, rendered with the container uid's
  # ownership.
  sops.templates."lunamultiplayer-server-config" = lib.mkIf (options ? nerdctl-containers) {
    owner = "container-${toString config.nerdctl-containers.${name}.uid}";
    group = "containers";
    mode = "0400";
    restartUnits = [ "nerdctl-${name}.service" ];
    # toml
    content = ''
      db_path = "/data/game-server-runner.db"
      port = 4479
      # What players type into the KSP client: single-label wildcard under
      # the public cloudflare zone to the vps, where frp tunnels the game
      # traffic (raw entry below).
      connect_url = "lunamultiplayer.polpetta.online:8800"
      # Luna's own data directory (see LUNAMULTIPLAYER_DIR); also holds
      # server.toml and the runner database.
      server_dir = "/data"
      minutes_before_stop = 15

      restic_enable = false

      [telegram]
      token = "${config.sops.placeholder."game-server-runner-telegram-token"}"
      username = "${config.sops.placeholder."game-server-runner-telegram-username"}"
      chat_ids = "${config.sops.placeholder."game-server-runner-telegram-chat-ids"}"
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
          imageRoot
        ];

        config.entrypoint = [ "/bin/game-server-runner" ];
      };

      # CONFIG_PATH is the only env var the runner reads itself. PATH so
      # `command = "Server"` resolves; the rest of the config lives in
      # config.toml (above). LUNAMULTIPLAYER_DIR is inherited by the
      # spawned server: the nix package patches Luna to store Config,
      # Universe, Plugins and logs under this directory instead of the
      # immutable package directory.
      environment = {
        PATH = "/bin";
        CONFIG_PATH = "/game-server-runner/config.toml";
        LUNAMULTIPLAYER_DIR = "/data";
      };

      environmentFiles = [ config.sops.templates."lunamultiplayer-server-env".path ];

      # The runner stops the server gracefully on its own SIGTERM
      # (container default stop signal), honoring server.toml's 30s
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
          hostPath = config.sops.templates."lunamultiplayer-server-config".path;
          containerPath = "/game-server-runner/config.toml";
          readOnly = true;
        }
      ];
    };

    web = {
      port = 4479;
      access = "public";
      # Default public domain (the historical lunamultiplayer.internal.
      # polpetta.online cannot be public: the wildcard cert and the
      # cloudflare wildcard only cover single-label names). Serving the
      # runner's web UI; Luna's built-in website stays off.
      nginx.extraConfig = ''
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
      '';
    };

    raw = [
      { port = 8800; proto = "udp"; access = "public"; } # game traffic
    ];
  };
}
