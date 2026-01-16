{
  pkgs,
  config,
  lib,
  ...
}:
let
  headscaleConfig = pkgs.writeText "headscale.yaml" ''
    server_url: https://headscale.polpetta.online
    listen_addr: 0.0.0.0:8080
    metrics_listen_addr: 0.0.0.0:9090
    grpc_listen_addr: 0.0.0.0:50443
    grpc_allow_insecure: false
    private_key_path: /var/lib/headscale/private.key
    noise:
      private_key_path: /var/lib/headscale/noise_private.key
    ip_prefixes:
      - fd7a:115c:a1e0::/48
      - 100.64.0.0/10
    derp:
      server:
        enabled: false
      urls:
        - https://controlplane.tailscale.com/derpmap/default
      paths: []
      auto_update_enabled: true
      update_frequency: 24h
    disable_check_updates: false
    ephemeral_node_inactivity_timeout: 30m
    node_pruning_enabled: false
    db_type: sqlite3
    db_path: /var/lib/headscale/db.sqlite
    acme_url: https://acme-v02.api.letsencrypt.org/directory
    acme_email: ""
    tls_letsencrypt_hostname: ""
    tls_client_auth_mode: relaxed
    tls_letsencrypt_cache_dir: /var/lib/headscale/cache
    tls_letsencrypt_challenge_type: HTTP-01
    tls_letsencrypt_listen: :80
    log:
      format: text
      level: info
    policy:
      mode: file
      path: ""
    dns_config:
      nameservers:
        - 1.1.1.1
        - 1.0.0.1
      domains: []
      magic_dns: true
      base_domain: internal.polpetta.online
    unix_socket: /var/run/headscale/headscale.sock
    unix_socket_permission: "0770"
    logtail:
      enabled: false
    randomize_client_port: false
  '';
in
{
  # System Configuration
  networking.firewall.allowedUDPPorts = [ 51820 ];
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
  };

  # Secrets (Placeholder - User must configure this)
  # sops.secrets.headplane_secrets = {
  #   sopsFile = ./secrets.yaml; 
  #   format = "yaml";
  # };

  # Container Configuration
  nerdctl-containers.headscale = {
    id = 20;
    imageToBuild = pkgs.nix-snapshotter.buildImage {
      name = "headscale";
      tag = "nix-local";
      config = {
        Entrypoint = [ "${lib.getExe pkgs.headscale}" ];
        Cmd = [ "serve" ];
        Env = [ "HEADSCALE_CONFIG=/etc/headscale/config.yaml" ];
      };
    };
    ports = [ "51820:51820/udp" ];
    volumes = [
      {
        hostPath = "/var/lib/headscale";
        containerPath = "/var/lib/headscale";
        userAccessible = true;
      }
      {
        hostPath = "${headscaleConfig}";
        containerPath = "/etc/headscale/config.yaml";
        readOnly = true;
      }
    ];
  };

  nerdctl-containers.headplane = {
    id = 21;
    imageToPull = "ghcr.io/tale/headplane";
    dependsOn = [ "headscale" ];
    environment = {
      HEADSCALE_URL = "http://10.0.1.20:8080";
      PORT = "3000";
    };
    environmentFiles = 
      if config.sops.secrets ? headplane_secrets 
      then [ config.sops.secrets.headplane_secrets.path ]
      else [ ]; 
  };
}
