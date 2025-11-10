{ pkgs, config, ... }:
let
  inherit ((import ./utils.nix) { inherit pkgs config; }) makeContainer;

  name = "cloudflared";
  baseSSDDir = "/mnt/SSD/apps/${name}";
in
makeContainer {
  inherit name;
  image = "docker.io/erisamoe/cloudflared";
  ip = "10.0.1.131";

  volumes = [
    "${baseSSDDir}:/etc/cloudflared:rw"
  ];
  adminOnlyDirs = [ baseSSDDir ];

  cmd = [
    "tunnel"
    "run"
    "nas"
  ];
}
