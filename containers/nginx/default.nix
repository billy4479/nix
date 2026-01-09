{ pkgs, config, ... }:
let
  name = "nginx";
  baseSSDDir = "/mnt/SSD/apps/${name}";
  certsDir = "/mnt/SSD/apps/certbot";

  cloudflaredAddress = "10.0.1.131";
  nginxConfig = pkgs.callPackage ./config.nix { inherit cloudflaredAddress; };
in
{
  nerdctl-containers.${name} = {
    imageToPull = "docker.io/nginx";
    id = 6;
    runByUser = false; # We need to bind port 80 and 433

    entrypoint = "nginx";
    cmd = [
      "-g"
      "daemon off;"
    ];

    volumes = [
      {
        hostPath = "${nginxConfig}/nginx.conf";
        containerPath = "/etc/nginx/nginx.conf";
        readOnly = true;
      }
      {
        hostPath = "${nginxConfig}/snippets";
        containerPath = "/etc/nginx/snippets";
        readOnly = true;
      }
      {
        hostPath = "${baseSSDDir}/logs";
        containerPath = "/var/log/nginx";
      }
      {
        hostPath = certsDir;
        containerPath = "/certs/";
        readOnly = true;
      }
    ];

    ports = [
      "80:80/tcp"
      "443:443/tcp"
    ];
  };
}
