{ pkgs, config, ... }:
let
  inherit ((import ./utils.nix) { inherit pkgs config; }) makeContainer;

  name = "opencloud";
  domain = "opencloud.polpetta.online";

  initialAdminPassword = "admin";

  baseSSDDir = "/mnt/SSD/apps/${name}";
  configDir = "${baseSSDDir}/config";
  appsDir = "${baseSSDDir}/apps";
  dataDir = "/mnt/HDD/apps/${name}";
in
makeContainer {
  inherit name;

  image = "docker.io/opencloudeu/opencloud-rolling";
  id = 14;

  environment = {
    "OC_INSECURE" = "false";
    "OC_URL" = "https://${domain}";
    "PROXY_HTTP_ADDR" = "10.0.1.14:9200";
    "PROXY_TLS" = "false";

    "IDM_ADMIN_PASSWORD" = initialAdminPassword;

    "FRONTEND_ARCHIVER_MAX_SIZE" = "10000000000";
    "FRONTEND_CHECK_FOR_UPDATES" = "true";

    "OC_SHARING_PUBLIC_SHARE_MUST_HAVE_PASSWORD" = "false";
    "OC_SHARING_PUBLIC_WRITEABLE_SHARE_MUST_HAVE_PASSWORD" = "false";
    "OC_PASSWORD_POLICY_DISABLED" = "true";
    "OC_PASSWORD_POLICY_BANNED_PASSWORDS_LIST" = "";
  };

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
}
