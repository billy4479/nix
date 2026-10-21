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

  # The web frontend's CSP must allow XHRs to the OIDC issuer (discovery,
  # token, userinfo all go to tsidp cross-origin). PROXY_CSP_CONFIG_FILE_
  # LOCATION deep-merges this over the embedded default, and the loader
  # concatenates directive lists — so the delta alone is enough.
  cspOverride = pkgs.writeText "opencloud-csp.yaml" ''
    directives:
      connect-src:
        - https://idp.internal.polpetta.online
  '';

  baseSSDDir = "/mnt/SSD/apps/${name}";
  configDir = "${baseSSDDir}/config";
  appsDir = "${baseSSDDir}/apps";
  dataDir = "/mnt/HDD/apps/${name}";
in
{
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    opencloud-oidc-client-id.key = "opencloud/oidc-client-id";
    opencloud-idm-admin-password.key = "opencloud/idm-admin-password";
  };

  sops.templates."opencloud-env".content = lib.mkIf (options ? nerdctl-containers) (
    # sh
    ''
      OC_OIDC_CLIENT_ID=${config.sops.placeholder.opencloud-oidc-client-id}
      IDM_ADMIN_PASSWORD=${config.sops.placeholder.opencloud-idm-admin-password}
    ''
  );

  sops.templates."opencloud-env".restartUnits = lib.mkIf (options ? nerdctl-containers) [
    "nerdctl-${name}.service"
  ];

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
        "PROXY_CSP_CONFIG_FILE_LOCATION" = "/etc/opencloud/csp-override.yaml";

        "OC_PASSWORD_POLICY_DISABLED" = "true";
        "OC_SHARING_PUBLIC_SHARE_MUST_HAVE_PASSWORD" = "true";
        "OC_SHARING_PUBLIC_WRITEABLE_SHARE_MUST_HAVE_PASSWORD" = "true";
        "FRONTEND_ARCHIVER_MAX_SIZE" = "10000000000";

        # Authentication via tsidp (external OIDC, tailnet-only). The web
        # frontend and the proxy read the issuer from OC_OIDC_ISSUER, the web
        # client id (registered via DCR with token_endpoint_auth_method
        # "none" — it is a secret-less public client, so not via the admin
        # UI) comes from the sops key opencloud/oidc-client-id, rendered
        # into the opencloud-env template. Full runbook:
        # docs/deployments/tsidp-opencloud.md.
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
        # Account resolution and auto-provisioning: the `email` claim is the
        # join key. Every headscale user's Email is
        # <username>@mail.polpetta.online (docs/TSIDP.md invariant), so the
        # claim is unique per user, unreachable by display-name edits, and
        # its local part equals the short username. Lookup runs against the
        # LDAP mail attribute; provisioning names fresh accounts after the
        # full address (OpenCloud explicitly allows email-shaped usernames).
        # Never change a headscale Email: a rename orphans the account —
        # the next login misses the lookup and autoprovisions a fresh one.
        "PROXY_USER_OIDC_CLAIM" = "email";
        "PROXY_USER_CS3_CLAIM" = "mail";
        "PROXY_AUTOPROVISION_ACCOUNTS" = "true";
        "PROXY_AUTOPROVISION_CLAIM_USERNAME" = "email";
        "PROXY_AUTOPROVISION_CLAIM_EMAIL" = "email";
        # Display name from the `name` claim ("Jack"); headscale guarantees a
        # non-empty value (its DisplayName falls back to email/username).
        "PROXY_AUTOPROVISION_CLAIM_DISPLAYNAME" = "name";
      };

      environmentFiles = [ config.sops.templates."opencloud-env".path ];

      volumes = [
        {
          hostPath = "${cspOverride}";
          containerPath = "/etc/opencloud/csp-override.yaml";
          readOnly = true;
        }
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
