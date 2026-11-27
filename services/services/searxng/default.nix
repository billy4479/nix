{
  config,
  pkgs,
  domain,
  lib,
  options,
  ...
}:
let
  name = "searxng";
  baseDir = "/mnt/SSD/apps/${name}";
in
{
  sops.secrets.searxng-env = lib.mkIf (options ? nerdctl-containers) {
    restartUnits = [ "nerdctl-searxng.service" ];
  };

  polpetta.services.${name} = {
    container = {
      id = 19;

      entrypoint = [ (lib.getExe pkgs.searxng) ];

      environment = {
        SEARXNG_SETTINGS_PATH = "/etc/searxng/settings.yml";
        SEARXNG_BIND_ADDRESS = "0.0.0.0";
        SEARXNG_PORT = "8888";
        SEARXNG_BASE_URL = "https://searxng.${domain}/";
        TMPDIR = "/cache";
      };

      environmentFiles = [ config.sops.secrets.searxng-env.path ];

      volumes = [
        {
          hostPath = "${pkgs.replaceVars ./settings.yml { inherit domain; }}";
          containerPath = "/etc/searxng/settings.yml";
          readOnly = true;
        }
        {
          hostPath = "${baseDir}/cache";
          containerPath = "/cache";
        }
      ];
    };

    web = {
      port = 8888;
      access = "tailnet-only";
      # T3 Code's search tooling uses the canonical HTTPS endpoint.
      allowedSources = [
        "100.64.0.0/10"
        "10.0.1.${toString config.polpetta.services.t3code.container.id}/32"
      ];
      probe.path = "/healthz";
    };
  };
}
