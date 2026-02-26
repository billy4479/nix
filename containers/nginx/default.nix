{ pkgs, ... }:
let
  name = "nginx";
  certsDir = "/mnt/SSD/apps/certbot/config";

  nginxConfig = pkgs.callPackage ./config.nix { };
in
{
  nerdctl-containers.${name} = {
    imageToPull = "docker.io/nginx";
    id = 6;

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
        hostPath = certsDir;
        containerPath = "/certs/";
        readOnly = true;
      }
    ];

    extraOptions = [
      "--cap-add=CAP_NET_BIND_SERVICE"
    ];

    ports = [
      "80:80/tcp"
      "443:443/tcp"
    ];
  };
}
