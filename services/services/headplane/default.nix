{
  pkgs,
  domain,
  lib,
  config,
  options,
  ...
}:
let
  # Lives under the historical `heascale` (sic) host path, see headscale.
  baseDir = "/mnt/SSD/apps/heascale";
  # Headplane validates Headscale's config and needs the same file paths.
  headscaleFiles = import ../headscale/files.nix {
    inherit pkgs domain;
    adminAddress = config.polpetta.generated.adminIngress.address;
  };
in
{
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    headplane-cookie-secret.key = "headplane/cookie-secret";
    headplane-oauth-client-id.key = "headplane/oauth-client-id";
    headplane-oauth-client-secret.key = "headplane/oauth-client-secret";
    headplane-headscale-api-key.key = "headplane/headscale-api-key";
  };

  sops.templates."headplane-env".content = lib.mkIf (options ? nerdctl-containers) (
    # sh
    ''
      HEADPLANE_SERVER__COOKIE_SECRET=${config.sops.placeholder.headplane-cookie-secret}
      HEADPLANE_OIDC__CLIENT_ID=${config.sops.placeholder.headplane-oauth-client-id}
      HEADPLANE_OIDC__CLIENT_SECRET=${config.sops.placeholder.headplane-oauth-client-secret}
      HEADPLANE_HEADSCALE__API_KEY=${config.sops.placeholder.headplane-headscale-api-key}
    ''
  );

  sops.templates."headplane-env".restartUnits = lib.mkIf (options ? nerdctl-containers) [
    "nerdctl-headplane.service"
  ];

  polpetta.services.headplane = {
    container = {
      id = 16;

      entrypoint = [ (lib.getExe pkgs.headplane) ];

      dependsOn = [ "headscale" ];

      environmentFiles = [ config.sops.templates."headplane-env".path ];

      volumes = headscaleFiles ++ [
        {
          hostPath = "${pkgs.replaceVars ./headplane.yaml { inherit domain; }}";
          containerPath = "/etc/headplane/config.yaml";
          readOnly = true;
        }
        {
          hostPath = "${baseDir}/headplane";
          containerPath = "/var/lib/headplane";
        }
      ];
    };

    web = {
      port = 3000;
      access = "tailnet";
      # / answers 401; /admin is the login page.
      probe.path = "/admin";
      # With OIDC enabled /admin redirects to the IdP; the redirect is the
      # liveness signal (see http_unauth in monitoring).
      probe.unauth = true;
    };
  };
}
