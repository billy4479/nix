{
  config,
  domain,
  pkgs,
  lib,
  options,
  ...
}:
let
  name = "ff";
  baseDir = "/mnt/SSD/apps/${name}";
in
{
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    ff-oauth-client-id.key = "ff/oauth-client-id";
    ff-oauth-client-secret.key = "ff/oauth-client-secret";
    ff-session-secret.key = "ff/session-secret";
  };

  sops.templates."ff-env".content = lib.mkIf (options ? nerdctl-containers) (
    # sh
    ''
      OIDC_ISSUER=https://idp.internal.${domain}
      OIDC_CLIENT_ID=${config.sops.placeholder."ff-oauth-client-id"}
      OIDC_CLIENT_SECRET=${config.sops.placeholder."ff-oauth-client-secret"}
      SESSION_SECRET=${config.sops.placeholder."ff-session-secret"}
    ''
  );

  sops.templates."ff-env".restartUnits = lib.mkIf (options ? nerdctl-containers) [
    "nerdctl-${name}.service"
  ];

  polpetta.services.${name} = {
    container = {
      id = 17;

      entrypoint = [ (lib.getExe pkgs.ff) ];

      environment = {
        PORT = "4479";
        ENVIRONMENT = "production";
        ORIGIN = "https://ff.internal.${domain}";
        FF_DATA_PATH = "/data";
      };

      # OIDC login against tsidp (docs/deployments/tsidp-ff.md): everyone the
      # IdP authenticates may use ff and is provisioned on first login; the
      # client id/secret come from the tsidp client registration, the session
      # secret signs ff's session cookies.
      environmentFiles = [ config.sops.templates."ff-env".path ];

      volumes = [
        {
          hostPath = baseDir;
          containerPath = "/data";
        }
      ];
    };

    web = {
      port = 4479;
      access = "tailnet";
      # The unauthenticated probe gets bounced to the OIDC login; that
      # redirect is the liveness signal (see http_unauth in monitoring).
      probe.unauth = true;
    };
  };
}
