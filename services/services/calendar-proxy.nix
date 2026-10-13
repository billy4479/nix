{
  pkgs,
  lib,
  config,
  options,
  ...
}:
let
  name = "calendar-proxy";
in
{
  sops.secrets.calendar-proxy-env = lib.mkIf (options ? nerdctl-containers) { };

  polpetta.services.${name} = {
    container = {
      id = 4;

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

      environment = {
        PORT = "4479";
        ENV = "prod";
        DONT_LOAD_DOTENV = "1";
      };

      environmentFiles = [ config.sops.secrets.calendar-proxy-env.path ];
    };

    web = {
      port = 4479;
      access = "public";
      # Answers 401 without a token; still proves the server is alive.
      probe.unauth = true;
    };
  };
}
