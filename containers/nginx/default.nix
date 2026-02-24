{ pkgs, lib, ... }:
let
  name = "nginx";
  certsDir = "/mnt/SSD/apps/certbot/config";

  externalTrafficFrom = "10.0.1.131";
  nginxConfig = pkgs.callPackage ./config.nix { inherit externalTrafficFrom; };

  etcFiles = pkgs.runCommand "etc-files" { } ''
    mkdir -p $out/etc
    echo "nobody:x:65534:65534:Unprivileged account:/var/empty:/run/current-system/sw/bin/nologin" > $out/etc/passwd
    echo "nogroup:x:65534:" > $out/etc/group
  '';
in
{
  nerdctl-containers.${name} = {
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      name = "nginx";
      tag = "nix-local";

      copyToRoot = with pkgs; [
        dockerTools.caCertificates
        nginx
        etcFiles
      ];

      config = {
        entrypoint = [ "${lib.getExe pkgs.nginx}" ];
        cmd = [
          "-g"
          "daemon off;"
        ];
      };
    };

    id = 6;
    runByUser = false; # We need to bind port 80 and 443

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

    ports = [
      "80:80/tcp"
      "443:443/tcp"
    ];
  };
}
