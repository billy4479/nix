{ config, ... }:
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
    imageToPull = "docker.io/opencloudeu/opencloud-rolling";
    id = 14;

    environment = {
      "OC_INSECURE" = "false";
      "OC_URL" = "https://${domain}";
      "PROXY_HTTP_ADDR" = "10.0.1.14:9200";
      "PROXY_TLS" = "false";

      "FRONTEND_ARCHIVER_MAX_SIZE" = "10000000000";
      "FRONTEND_CHECK_FOR_UPDATES" = "true";
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
