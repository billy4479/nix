{
  pkgs,
  domain,
  config,
  lib,
  options,
  ...
}:
let
  name = "tsidp";
  baseDir = "/mnt/SSD/apps/${name}";
in
{
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    tsidp-authkey.key = "tsidp/authkey";
  };

  sops.templates."tsidp-env" = lib.mkIf (options ? nerdctl-containers) {
    content = # sh
      ''
        TS_AUTHKEY=${config.sops.placeholder.tsidp-authkey}
      '';
    restartUnits = [ "nerdctl-${name}.service" ];
  };

  polpetta.services.${name} = {
    container = {
      id = 25;
      dependsOn = [ "headscale" ];

      entrypoint = [ (lib.getExe pkgs.tsidp) ];

      cmd = [
        "-dir"
        "/var/lib/tsidp"
        "-listen"
        "0.0.0.0:8080"
        "-trusted-proxy"
        "10.0.1.6"
        "-server-url"
        "https://idp.${domain}"
      ];

      environment = {
        TS_LOGIN_SERVER = "https://headscale.${domain}:443";
        TS_HOSTNAME = "idp";
        TAILSCALE_USE_WIP_CODE = "1";
        TSIDP_LOG = "info";
      };

      environmentFiles = [ config.sops.templates."tsidp-env".path ];

      volumes = [
        {
          hostPath = "${baseDir}/lib";
          containerPath = "/var/lib/tsidp";
        }
      ];
    };

    web = {
      port = 8080;
      access = "tailnet-only";
      # OIDC relying parties need discovery, token exchange and userinfo
      # over the canonical HTTPS issuer even when they run on the bridge.
      allowedSources = [
        "100.64.0.0/10"
      ]
      ++ map (client: "10.0.1.${toString config.polpetta.services.${client}.container.id}/32") [
        "ff"
        "game-server-runner"
        "giuoco-del-divertimento"
        "grafana"
        "headplane"
        "immich-server"
        "jellyfin"
        "lunamultiplayer"
        "opencloud"
        "outline"
        "radicale"
      ];
      # The service name is tsidp, but relying parties know it as idp.
      domain = "idp.${domain}";

      # / does WhoIs and 500s for non-tailnet peers (e.g. the blackbox
      # probe); the discovery endpoint is auth-free and proves tsidp is
      # actually serving OIDC.
      probe.path = "/.well-known/openid-configuration";
    };
  };
}
