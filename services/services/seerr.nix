{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.polpetta.seerrMemberAccess = lib.mkEnableOption ''
    member access to Seerr (enable only after completing the admin-only setup wizard)
  '';

  config.polpetta.services.seerr = {
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
      access = if config.polpetta.seerrMemberAccess then "tailnet" else "admin-only";
      probe.path = "/api/v1/status";
    };
  };
}
