{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  name = "mircrewrr";
  baseDir = "/mnt/SSD/apps/${name}";
  byparrIp = "10.0.1.134";
in
{
  # sops keys (in secrets-repo, serverone.yaml):
  # - mircrewrr/username
  # - mircrewrr/password
  # - mircrewrr/api-key
  # The stack envs are only the initial configuration: once the admin panel
  # has been used, config.json (in the data volume) takes precedence.
  sops.secrets = lib.mkIf (options ? nerdctl-containers) {
    mircrewrr-username.key = "mircrewrr/username";
    mircrewrr-password.key = "mircrewrr/password";
    mircrewrr-api-key.key = "mircrewrr/api-key";
  };

  sops.templates."mircrewrr-env".content = lib.mkIf (options ? nerdctl-containers) (
    # sh
    ''
      MIRCREW_USERNAME=${config.sops.placeholder."mircrewrr-username"}
      MIRCREW_PASSWORD=${config.sops.placeholder."mircrewrr-password"}
      MIRCREW_API_KEY=${config.sops.placeholder."mircrewrr-api-key"}
    ''
  );

  sops.templates."mircrewrr-env".restartUnits = lib.mkIf (options ? nerdctl-containers) [
    "nerdctl-${name}.service"
  ];

  polpetta.services.${name} = {
    container = {
      id = 135;

      entrypoint = [ (lib.getExe pkgs.mircrewrr) ];

      # Cloudflare Turnstile solves go through the byparr container.
      dependsOn = [ "byparr" ];

      environment = {
        PROXY_PORT = "9696";
        FLARESOLVERR_URL = "http://${byparrIp}:8191";
      };

      environmentFiles = [ config.sops.templates."mircrewrr-env".path ];

      volumes = [
        {
          hostPath = baseDir;
          containerPath = "/var/lib/mircrewrr";
        }
      ];
    };

    # Torznab for prowlarr/radarr/sonarr and the admin panel both ride on the
    # same port; the API key guards everything, so tailnet access is enough.
    web = {
      port = 9696;
      access = "tailnet";
      probe.path = "/health";
    };
  };
}
