{
  config,
  pkgs,
  ...
}:
let
  name = "searxng";
  baseDir = "/mnt/SSD/apps/${name}";
in
{
  sops.secrets.searxng-env = { };

  nerdctl-containers.${name} = {
    id = 19;
    useNginx = true;

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
      SEARXNG_BASE_URL = "https://searxng.internal.polpetta.online/";
      TMPDIR = "/cache";
    };

    environmentFiles = [ config.sops.secrets.searxng-env.path ];

    volumes = [
      {
        hostPath = "${./settings.yml}";
        containerPath = "/etc/searxng/settings.yml";
        readOnly = true;
      }
      {
        hostPath = "${baseDir}/cache";
        containerPath = "/cache";
      }
    ];
  };
}
