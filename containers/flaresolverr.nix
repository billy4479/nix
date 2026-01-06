{ pkgs, config, ... }:
let
  name = "flaresolverr";
  baseSSDDir = "/mnt/SSD/apps/${name}";
  inherit (import ./utils.nix { inherit pkgs config; }) makeContainer;
in
makeContainer {
  inherit name;
  image = "localhost/flaresolverr:latest";
  imageFile = pkgs.dockerTools.buildLayeredImage {

    inherit name;
    tag = "latest";

    contents = with pkgs; [
      flaresolverr
    ];

    config = {
      EntryPoint = [ "flaresolverr" ];
      WorkingDir = "/app";
    };
  };
  ip = "10.0.1.133";

  environment = {
    "LOG_LEVEL" = "info";
  };

  volumes = [
    {
      hostPath = "${baseSSDDir}/local";
      containerPath = "/app/.local";
    }
  ];

  tmpfs = [
    "/tmp"
    "/app/.cache"
  ];
}
