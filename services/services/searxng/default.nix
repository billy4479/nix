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

      imageToBuild = pkgs.nix-snapshotter.buildImage {
        inherit name;
        tag = "nix-local";

        copyToRoot = with pkgs; [
          dockerTools.caCertificates
          searxng
        ];

        config.entrypoint = [ "/bin/searxng-run" ];
      };

      environment = {
        SEARXNG_SETTINGS_PATH = "/etc/searxng/settings.yml";
        SEARXNG_BIND_ADDRESS = "0.0.0.0";
        SEARXNG_PORT = "8888";
        SEARXNG_BASE_URL = "https://searxng.internal.${domain}/";
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
      access = "tailnet";
      probe.path = "/healthz";
    };
  };
}
