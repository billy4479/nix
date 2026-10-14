{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  name = "opencloud";
  domain = "opencloud.polpetta.online";

  baseSSDDir = "/mnt/SSD/apps/${name}";
  configDir = "${baseSSDDir}/config";
  appsDir = "${baseSSDDir}/apps";
  dataDir = "/mnt/HDD/apps/${name}";
in
{
  sops.secrets.opencloud-env = lib.mkIf (options ? nerdctl-containers) { };

  polpetta.services.${name} = {
    container = {
      id = 14;

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";

        copyToRoot = with pkgs; [
          dockerTools.caCertificates
          dockerTools.binSh
          opencloud
        ];

        config = {
          entrypoint = [ "/bin/sh" ];
          env = [
            "WEB_ASSET_CORE_PATH=${pkgs.opencloud.web}"
            "OC_CONFIG_DIR=/etc/opencloud"
            "OC_BASE_DATA_PATH=/var/lib/opencloud"
          ];
        };
      };

      environment = {
        # These are awfully undocumented, some are here but the list is incomplete
        # https://docs.opencloud.eu/docs/dev/server/configuration/global-environment-variables
        "OC_INSECURE" = "false";
        "OC_URL" = "https://${domain}";
        "PROXY_HTTP_ADDR" = "10.0.1.14:9200";
        "PROXY_TLS" = "false";

        "FRONTEND_ARCHIVER_MAX_SIZE" = "10000000000";

        # Authentication via tsidp (external OIDC, tailnet-only). The web
        # frontend and the proxy read the issuer from OC_OIDC_ISSUER, the web
        # client id (registered via DCR with token_endpoint_auth_method
        # "none" — it is a secret-less public client, so not via the admin
        # UI) comes from the sops env file as OC_OIDC_CLIENT_ID. Full
        # runbook: docs/TSIDP.md.
        "OC_EXCLUDE_RUN_SERVICES" = "idp";
        "OC_OIDC_ISSUER" = "https://idp.internal.polpetta.online";
        # tsidp access tokens are opaque strings, not JWTs, so the proxy must
        # validate them (and read claims) via the userinfo endpoint. The
        # upstream default 'jwt' would try to parse them as JWTs and fail.
        "PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD" = "none";
        # Serve the issuer's discovery document under OC_URL so desktop
        # clients on the tailnet can find tsidp through the public URL.
        "PROXY_OIDC_REWRITE_WELLKNOWN" = "true";
        # No local authentication at all: OC_URL stays public (for share
        # links) and must not offer any login path to outsiders.
        "PROXY_ENABLE_BASIC_AUTH" = "false";
        # Account resolution and auto-provisioning: tsidp's userinfo carries
        # `username` (the short headscale username, derived by tsidp from
        # the WhoIs display name), `email` (the headscale Email field, a
        # real address) and `name` (the headscale display name, e.g.
        # "Jack"). `username` is the only claim guaranteed on every login,
        # so it maps the account lookup;
        # provisioning happens in the built-in IDM, which keeps running.
        "PROXY_USER_OIDC_CLAIM" = "username";
        "PROXY_USER_CS3_CLAIM" = "username";
        "PROXY_AUTOPROVISION_ACCOUNTS" = "true";
        "PROXY_AUTOPROVISION_CLAIM_USERNAME" = "username";
        "PROXY_AUTOPROVISION_CLAIM_EMAIL" = "email";
        # Display name from the `name` claim ("Jack"); headscale guarantees a
        # non-empty value (its DisplayName falls back to email/username).
        "PROXY_AUTOPROVISION_CLAIM_DISPLAYNAME" = "name";
      };

      environmentFiles = [ config.sops.secrets.opencloud-env.path ];

      volumes = [
        {
          hostPath = configDir;
          containerPath = "/etc/opencloud";
        }
        {
          hostPath = dataDir;
          containerPath = "/var/lib/opencloud";
        }
        {
          hostPath = appsDir;
          containerPath = "/var/lib/opencloud/web/assets/apps";
        }
      ];

      entrypoint = "/bin/sh";
      cmd = [
        "-c"
        "opencloud init || true; opencloud server"
      ];
    };

    web = {
      port = 9200;
      access = "public";
      # Deliberately unbuffered: sync clients pull files in parallel and
      # sizes are unbounded, so buffering multi-GB responses to the 2g tmpfs
      # would risk ENOSPC mid-transfer and burn RAM. ocis streams cheaply.
      nginx.extraConfig = ''
        client_max_body_size 500000M;
        proxy_request_buffering off;
        proxy_read_timeout 3600;
        send_timeout 3600;
        proxy_buffering off;
      '';
    };
  };
}
