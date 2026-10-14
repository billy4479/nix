{
  config,
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
      OIDC_ISSUER=https://idp.internal.polpetta.online
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

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";

        copyToRoot = with pkgs; [
          dockerTools.caCertificates
          ff
        ];

        config.entrypoint = [ "/bin/ff" ];
      };

      environment = {
        PORT = "4479";
        ENVIRONMENT = "production";
        ORIGIN = "https://ff.internal.polpetta.online";
        FF_DATA_PATH = "/data";
        # Authorization policy (fail closed): only this headscale username
        # may use ff; anybody else who authenticates gets a 403 page.
        ALLOWED_USERNAME = "jack";
      };

      # OIDC login against tsidp (docs/TSIDP.md): the app itself allows only
      # the headscale user `jack`; the client id/secret come from the tsidp
      # client registration, the session secret signs ff's session cookies.
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
    };
  };
}
