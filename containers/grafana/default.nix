{
  config,
  pkgs,
  ...
}:
let
  name = "grafana";
  baseDir = "/mnt/SSD/apps/${name}";
in
{
  sops.secrets = {
    grafana-admin-password.key = "grafana/admin-password";
    grafana-secret-key.key = "grafana/secret-key";
  };

  sops.templates."grafana-env".content = # sh
    ''
      GF_SECURITY_ADMIN_PASSWORD=${config.sops.placeholder."grafana-admin-password"}
      GF_SECURITY_SECRET_KEY=${config.sops.placeholder."grafana-secret-key"}
    '';

  sops.templates."grafana-env".restartUnits = [ "nerdctl-${name}.service" ];

  nerdctl-containers.${name} = {
    id = 23;
    useNginx = true;

    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      copyToRoot = with pkgs; [
        dockerTools.caCertificates
        grafana
        tzdata
      ];

      config = {
        entrypoint = [ "${pkgs.grafana}/bin/grafana" "server" ];
        cmd = [ "--homepath=${pkgs.grafana}/share/grafana" ];
        env = [
          "GF_PATHS_DATA=/var/lib/grafana"
          "GF_PATHS_LOGS=/var/lib/grafana/logs"
          "GF_PATHS_PLUGINS=/var/lib/grafana/plugins"
          "GF_PATHS_PROVISIONING=/etc/grafana/provisioning"
          "ZONEINFO=${pkgs.tzdata}/share/zoneinfo"
        ];
      };
    };

    environment = {
      GF_SECURITY_ADMIN_USER = "admin";
      GF_SERVER_ROOT_URL = "https://${name}.internal.polpetta.online";
      GF_USERS_ALLOW_SIGN_UP = "false";
      GF_AUTH_ANONYMOUS_ENABLED = "false";
      GF_ANALYTICS_REPORTING_ENABLED = "false";
      GF_ANALYTICS_CHECK_FOR_UPDATES = "false";
    };

    environmentFiles = [ config.sops.templates."grafana-env".path ];

    volumes = [
      {
        hostPath = "${baseDir}/lib";
        containerPath = "/var/lib/grafana";
      }
      {
        hostPath = "${./provisioning/datasources/prometheus.yaml}";
        containerPath = "/etc/grafana/provisioning/datasources/prometheus.yaml";
        readOnly = true;
      }
      {
        hostPath = "${./provisioning/dashboards/provider.yaml}";
        containerPath = "/etc/grafana/provisioning/dashboards/provider.yaml";
        readOnly = true;
      }
      {
        hostPath = "${./dashboards}";
        containerPath = "/etc/grafana/dashboards";
        readOnly = true;
      }
    ];
  };
}
