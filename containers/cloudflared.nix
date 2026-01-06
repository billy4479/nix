{ pkgs, config, ... }:
let
  inherit ((import ./utils.nix) { inherit pkgs config; }) makeContainer;

  name = "cloudflared";
  baseSSDDir = "/mnt/SSD/apps/${name}";
in
makeContainer {
  inherit name;
  image = "docker.io/erisamoe/cloudflared";
  id = 131;

  volumes = [
    {
      hostPath = baseSSDDir;
      containerPath = "/etc/cloudflared";
    }
  ];

  cmd = [
    "tunnel"
    "run"
    "nas"
  ];
}
