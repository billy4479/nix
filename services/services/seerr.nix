{ lib, pkgs, ... }:
{
  polpetta.services.seerr = {
    container = {
      id = 29;
      entrypoint = [ (lib.getExe pkgs.seerr) ];
      environment = {
        CONFIG_DIRECTORY = "/config";
        PORT = "5055";
      };
      volumes = [
        {
          hostPath = "/mnt/SSD/apps/seerr";
          containerPath = "/config";
        }
      ];
    };

    web = {
      port = 5055;
      access = "tailnet";
      probe.path = "/api/v1/status";
    };
  };
}
