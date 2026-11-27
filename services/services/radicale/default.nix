{
  config,
  domain,
  pkgs,
  lib,
  options,
  ...
}:
let
  name = "radicale";
  origin = "https://${name}.${domain}";
  state = "/data";
  runtime = import ./runtime.nix { inherit pkgs; };
  radicaleConfig = pkgs.writeText "radicale.conf" ''
    [auth]
    type = htpasswd
    htpasswd_filename = ${state}/htpasswd
    htpasswd_encryption = bcrypt
    htpasswd_cache = False
    cache_logins = False

    [rights]
    type = owner_only

    [storage]
    filesystem_folder = ${state}/collections

    [web]
    type = none
  '';
  # The image follows the entrypoint's Nix closure, not runtime args or env.
  start = pkgs.writeShellScript "radicale-start" ''
    export RADICALE_CONFIG=${radicaleConfig}
    exec ${runtime}/bin/gunicorn --chdir ${./.} --bind 0.0.0.0:5232 \
      --threads 4 --umask 0o077 'landing:create_app()' "$@"
  '';
in
{
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    radicale-oauth-client-id.key = "radicale/oauth-client-id";
    radicale-oauth-client-secret.key = "radicale/oauth-client-secret";
    radicale-session-secret.key = "radicale/session-secret";
    radicale-credential-key.key = "radicale/credential-key";
  };

  sops.templates."radicale-env" = lib.mkIf (options ? nerdctl-containers) {
    content = # sh
      ''
        OIDC_CLIENT_ID=${config.sops.placeholder.radicale-oauth-client-id}
        OIDC_CLIENT_SECRET=${config.sops.placeholder.radicale-oauth-client-secret}
        SESSION_SECRET=${config.sops.placeholder.radicale-session-secret}
        CREDENTIAL_KEY=${config.sops.placeholder.radicale-credential-key}
      '';
    restartUnits = [ "nerdctl-${name}.service" ];
  };

  polpetta.services.${name} = {
    container = {
      id = 30;
      entrypoint = [ "${start}" ];
      environment = {
        CALENDAR_ORIGIN = origin;
        CALENDAR_LEGACY_ORIGIN = "https://${name}.internal.${domain}";
        CALENDAR_STATE = state;
        OIDC_ISSUER = "https://idp.${domain}";
        RADICALE_CONFIG = "${radicaleConfig}";
        PYTHONDONTWRITEBYTECODE = "1";
      };
      environmentFiles = [ config.sops.templates."radicale-env".path ];
      volumes = [
        {
          hostPath = "/mnt/SSD/apps/${name}";
          containerPath = state;
        }
      ];
    };

    web = {
      port = 5232;
      access = "tailnet-only";
      probe.path = "/healthz";
    };
  };
}
