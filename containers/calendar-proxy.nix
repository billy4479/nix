{
  pkgs,
  config,
  ...
}:
let
  name = "calendar-proxy";
in
{
  sops.secrets.calendar-proxy-env = { };

  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      copyToRoot = with pkgs; [
        dockerTools.caCertificates
        calendar-proxy
      ];

      config.entrypoint = [
        "/bin/calendar-proxy-v2"
      ];
    };
    id = 4;

    environment = {
      PORT = "4479";
      ENV = "prod";
      DONT_LOAD_DOTENV = "1";
    };

    environmentFiles = [ config.sops.secrets.calendar-proxy-env.path ];
  };
}
