{
  pkgs,
  config,
  ...
}:
let
  name = "nginx";
  certsDir = "/mnt/SSD/apps/certbot/config";

  externalTrafficFrom = "10.0.1.${toString config.nerdctl-containers.frp.id}";
  nginxConfig = pkgs.callPackage ./config.nix { inherit externalTrafficFrom; };
in
{
  polpetta.externalTrafficFrom = externalTrafficFrom;

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
        hostPath = "${config.polpetta.generated.nginxVhostsFile}";
        containerPath = "/etc/nginx/vhosts.conf";
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

    capabilities = [ "CAP_NET_BIND_SERVICE" ];
    extraOptions = [ "--ulimit=nofile=65535:65535" ];

    # nginx spills buffered proxied responses/uploads (proxy_temp_path,
    # client_body_temp_path) to /tmp. The 128m default aborts any transfer
    # >128m mid-stream (ENOSPC on the tmpfs), e.g. downloading big immich
    # originals. 2g covers several concurrent large transfers; tmpfs pages
    # are RAM, so keep an eye on host memory (serverone has ~6g available).
    tmpfs = [ "/tmp:size=2g" ];

    ports = [
      "80:80/tcp"
      "443:443/tcp"
    ];
  };
}
