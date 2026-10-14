{
  config,
  pkgs,
  lib,
  options,
  ...
}:
let
  name = "giuoco-del-divertimento";
  baseDir = "/mnt/SSD/apps/${name}";
in
{
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    giuoco-oauth-client-id.key = "giuoco/oauth-client-id";
    giuoco-oauth-client-secret.key = "giuoco/oauth-client-secret";
    giuoco-session-secret.key = "giuoco/session-secret";
  };

  sops.templates."giuoco-env".content = lib.mkIf (options ? nerdctl-containers) (
    # sh
    ''
      OIDC_ISSUER=https://idp.internal.polpetta.online
      OIDC_CLIENT_ID=${config.sops.placeholder."giuoco-oauth-client-id"}
      OIDC_CLIENT_SECRET=${config.sops.placeholder."giuoco-oauth-client-secret"}
      SESSION_SECRET=${config.sops.placeholder."giuoco-session-secret"}
    ''
  );

  sops.templates."giuoco-env".restartUnits = lib.mkIf (options ? nerdctl-containers) [
    "nerdctl-${name}.service"
  ];

  polpetta.services.${name} = {
    container = {
      id = 18;

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";

        copyToRoot = with pkgs; [
          dockerTools.caCertificates
          giuoco-del-divertimento
        ];

        config.entrypoint = [ "/bin/giuoco-del-divertimento" ];
      };

      environment = {
        PORT = "4479";
        ENVIRONMENT = "production";
        ORIGIN = "https://giuoco.polpetta.online";
        DATABASE_URL = "/data/items.db";
      };

      # OIDC login against tsidp (docs/TSIDP.md): the game is publicly
      # readable/playable, any tailnet member who logs in may add cards.
      # The client id/secret come from the tsidp client registration, the
      # session secret signs giuoco's session cookies.
      environmentFiles = [ config.sops.templates."giuoco-env".path ];

      volumes = [
        {
          hostPath = baseDir;
          containerPath = "/data";
        }
      ];
    };

    web = {
      port = 4479;
      access = "public";
      # Short name instead of the default <name>.polpetta.online.
      domain = "giuoco.polpetta.online";
    };
  };
}
