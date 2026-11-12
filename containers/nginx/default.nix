{
  pkgs,
  domain,
  config,
  ...
}:
let
  name = "nginx";
  certsDir = "/mnt/SSD/apps/certbot/config";

  # The public web edge: the vps SNI demuxer relays to nginx over the
  # wireguard tunnel, so tunnel-terminated connections arrive from the vps's
  # tunnel address with the real client IP in the proxy_protocol header.
  # Trusted for real_ip restoration and denied for non-public tiers (defense
  # in depth: without a valid PP header the source would stay the edge
  # address, which matches `allow 10.0.0.0/8`).
  # Keep the retiring frp address trusted and denied until both hosts have
  # migrated. Reserve 10.0.1.131 while it remains in this list.
  externalTrafficFrom = [
    "10.100.0.1"
    "10.0.1.131"
  ];
  nginxConfig = pkgs.callPackage ./config.nix { inherit externalTrafficFrom domain; };
  homepage = pkgs.callPackage ../../sites/homepage { };
in
{
  polpetta.externalTrafficFrom = externalTrafficFrom;

  nerdctl-containers.${name} = {
    copyToRoot = [ pkgs.nginx ];
    entrypoint = [ "/bin/nginx" ];

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
        hostPath = "${homepage}";
        containerPath = "/srv/homepage";
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
