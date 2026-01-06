{ pkgs, config, ... }:
let
  name = "flaresolverr";
  baseSSDDir = "/mnt/SSD/apps/${name}";
  inherit (import ./utils.nix { inherit pkgs config; }) makeContainer;
in
makeContainer {
  inherit name;
  image = "localhost/flaresolverr:latest";
  imageFile = pkgs.dockerTools.buildImage {

    inherit name;
    tag = "latest";

    copyToRoot = with pkgs; [
      flaresolverr
    ];

    config = {
      EntryPoint = [ "flaresolverr" ];
      WorkingDir = "/app";
    };
  };
  id = 133;

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
