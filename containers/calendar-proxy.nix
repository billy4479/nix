{
  pkgs,
  config,
  extraPkgs,
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

      config.entrypoint = [
        "${extraPkgs.my-packages.calendar-proxy}/bin/calendar-proxy"
      ];
    };
    id = 4;

    environment = {
      PORT = "4479";
      ENV = "prod";
    };

    environmentFiles = [ config.sops.secrets.calendar-proxy-env.path ];
  };
}
