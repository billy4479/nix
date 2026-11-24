{
  domain,
  flakeInputs,
  lib,
  pkgs,
  ...
}:
let
  port = 4479;
  package = flakeInputs.laurea.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  polpetta.services.laurea = {
    container = {
      id = 28;
      entrypoint = [ (lib.getExe package) ];

      environment = {
        HOST = "0.0.0.0";
        PORT = toString port;
        ORIGIN = "https://laurea.${domain}";
        DATABASE_PATH = "/data/laurea.sqlite";
        # nginx overwrites this header with the real client address.
        ADDRESS_HEADER = "x-real-ip";
      };

      volumes = [
        {
          hostPath = "/mnt/SSD/apps/laurea";
          containerPath = "/data";
        }
      ];
    };

    web = {
      inherit port;
      access = "public";
    };

  };
}
