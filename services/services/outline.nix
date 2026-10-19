{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  name = "outline";
  baseDir = "/mnt/SSD/apps/${name}";
  # Shared plumbing containers, see services/services/{postgresql,outline-valkey}.
  postgresIp = "10.0.1.130";
  redisIp = "10.0.1.133";
in
{
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    outline-secret-key.key = "outline/secret-key";
    outline-utils-secret.key = "outline/utils-secret";
    outline-db-password.key = "outline/db-password";
    outline-oauth-client-id.key = "outline/oauth-client-id";
    outline-oauth-client-secret.key = "outline/oauth-client-secret";
  };

  sops.templates."outline-env".content = lib.mkIf (options ? nerdctl-containers) (
    # sh
    ''
      SECRET_KEY=${config.sops.placeholder.outline-secret-key}
      UTILS_SECRET=${config.sops.placeholder.outline-utils-secret}
      DATABASE_URL=postgres://outline:${config.sops.placeholder.outline-db-password}@${postgresIp}:5432/outline?sslmode=disable
      OIDC_CLIENT_ID=${config.sops.placeholder.outline-oauth-client-id}
      OIDC_CLIENT_SECRET=${config.sops.placeholder.outline-oauth-client-secret}
    ''
  );

  sops.templates."outline-env".restartUnits = lib.mkIf (options ? nerdctl-containers) [
    "nerdctl-${name}.service"
  ];

  polpetta.services.${name} = {
    container = {
      id = 24;

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";

        copyToRoot = with pkgs; [
          dockerTools.caCertificates
          outline
          tzdata
        ];

        config.entrypoint = [ "${pkgs.outline}/bin/outline-server" ];
      };

      # Outline resolves its onboarding content and public assets relative to
      # the working directory (the NixOS module does the same).
      workingDirectory = "${pkgs.outline}/share/outline";

      environment = {
        URL = "https://${name}.internal.polpetta.online";
        PORT = "3000";
        # nginx terminates TLS and forwards X-Forwarded-Proto, so Outline only
        # uses this to mark cookies secure and redirect plain http.
        FORCE_HTTPS = "true";
        ENABLE_UPDATES = "false";

        REDIS_URL = "redis://${redisIp}:6379";

        FILE_STORAGE = "local";
        FILE_STORAGE_LOCAL_ROOT_DIR = "/var/lib/outline/data";
        FILE_STORAGE_UPLOAD_MAX_SIZE = "262144000";

        # Auth against tsidp (docs/TSIDP.md): the client id/secret come from
        # the tsidp client registration, the callback path is fixed by
        # Outline (${URL}/auth/oidc.callback).
        OIDC_AUTH_URI = "https://idp.internal.polpetta.online/authorize";
        OIDC_TOKEN_URI = "https://idp.internal.polpetta.online/token";
        OIDC_USERINFO_URI = "https://idp.internal.polpetta.online/userinfo";
        OIDC_DISPLAY_NAME = "tsidp";
        OIDC_SCOPES = "openid profile email";
        # tsidp's userinfo has `username` while the ID token carries the same
        # value as `preferred_username`; Outline checks the userinfo first and
        # falls back to the ID token, so the default claim name covers both
        # (the short headscale username, see the claims section of TSIDP.md).
        OIDC_USERNAME_CLAIM = "preferred_username";
      };

      environmentFiles = [ config.sops.templates."outline-env".path ];

      volumes = [
        {
          hostPath = "${baseDir}/data";
          containerPath = "/var/lib/outline/data";
        }
      ];

      dependsOn = [
        "postgresql"
        "outline-valkey"
      ];
    };

    web = {
      port = 3000;
      access = "tailnet";
      # Match FILE_STORAGE_UPLOAD_MAX_SIZE, otherwise nginx 413s large
      # attachment uploads before Outline ever sees them.
      nginx.extraConfig = ''
        client_max_body_size 262144000;
      '';
    };
  };
}
