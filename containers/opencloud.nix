{
  pkgs,
  lib,
  config,
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
  sops.secrets.opencloud-env = { };

  nerdctl-containers.${name} = {
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
          "IDP_ASSET_PATH=${pkgs.opencloud.idp-web}/assets"
          "OC_CONFIG_DIR=/etc/opencloud"
          "OC_BASE_DATA_PATH=/var/lib/opencloud"
        ];
      };
    };

    id = 14;
    useNginx = true;

    environment = {
      # These are awfully undocumented, some are here but the list is incomplete
      # https://docs.opencloud.eu/docs/dev/server/configuration/global-environment-variables
      "OC_INSECURE" = "false";
      "OC_URL" = "https://${domain}";
      "PROXY_HTTP_ADDR" = "10.0.1.14:9200";
      "PROXY_TLS" = "false";

      "FRONTEND_ARCHIVER_MAX_SIZE" = "10000000000";
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
}
