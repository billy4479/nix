{ pkgs, config, ... }:
let
  name = "nginx";
  baseSSDDir = "/mnt/SSD/apps/${name}";
  certsDir = "/mnt/SSD/apps/certbot";
  inherit ((import ../utils.nix) { inherit pkgs config; }) makeContainer;

  cloudflaredAddress = "10.0.1.131";
  nginxConfig = pkgs.callPackage ./config.nix { inherit cloudflaredAddress; };
in
makeContainer {
  inherit name;
  image = "docker.io/nginx";
  ip = "10.0.1.6";
  runByUser = false; # We need to bind port 80 and 433

  volumes = [
    "${nginxConfig}/nginx.conf:/etc/nginx/nginx.conf:ro"
    "${nginxConfig}/snippets:/etc/nginx/snippets:ro"

    "${baseSSDDir}/logs:/var/log/nginx:rw"
    "${certsDir}:/certs/:ro"
  ];
  adminOnlyDirs = [ baseSSDDir ];

  ports = [
    "80:80/tcp"
    "443:443/tcp"
  ];
}
