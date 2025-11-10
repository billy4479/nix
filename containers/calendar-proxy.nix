{
  pkgs,
  config,
  extraPkgs,
  ...
}:
let
  inherit ((import ./utils.nix) { inherit pkgs config; }) makeContainer;
  name = "calendar-proxy";
in
{
  sops.secrets.calendar-proxy-env = { };
}
// makeContainer {
  inherit name;
  image = "localhost/calendar-proxy:latest";
  imageFile = extraPkgs.my-packages.containers.calendar-proxy;
  ip = "10.0.1.4";

  environment = {
    PORT = "4479";
    ENV = "prod";
  };

  environmentFiles = [ config.sops.secrets.calendar-proxy-env.path ];
}
