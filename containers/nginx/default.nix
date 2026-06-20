{ pkgs, ... }:
let
  name = "nginx";
  certsDir = "/mnt/SSD/apps/certbot/config";

  externalTrafficFrom = "10.0.1.131";
  nginxConfig = pkgs.callPackage ./config.nix { inherit externalTrafficFrom; };
in
{
  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";

      config = {
        entrypoint = [ "/bin/nginx" ];
      };

      copyToRoot = [ pkgs.nginx ];
    };

    id = 6;
    cmd = [
      "-e"
      "/dev/stdout"
      "-g"
      "daemon off;"
    ];

    volumes = [
      {
        hostPath = "${nginxConfig}/nginx.conf";
        containerPath = "${pkgs.nginx}/conf/nginx.conf";
        readOnly = true;
      }
      {
        hostPath = "${nginxConfig}/snippets";
        containerPath = "/etc/nginx/snippets";
        readOnly = true;
      }
      {
        hostPath = "${pkgs.nginx}/conf/mime.types";
        containerPath = "/etc/nginx/mime.types";
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
      "--ulimit=nofile=65535:65535"
    ];

    ports = [
      "80:80/tcp"
      "443:443/tcp"
    ];
  };
}
