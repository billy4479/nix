{ config, ... }:
{
  sops.secrets.rathole-credentials = { };

  services.rathole = {
    enable = true;
    role = "client";

    credentialsFile = config.sops.secrets.rathole-credentials.path;

    settings.client = {
      remote_addr = "87.106.25.93:2333";
      transport = {
        type = "noise";
        noise.remote_public_key = "Sy21aaybZ2mWzGjRbX5bv5TP+BaXAO6L96iiySAtjxM=";
      };

      services = {
        nginx_http = {
          type = "tcp";
          local_addr = "10.0.1.6:80";
        };
        nginx_https = {
          type = "tcp";
          local_addr = "10.0.1.6:443";
        };
        minecraft_java = {
          type = "tcp";
          local_addr = "10.0.1.13:25565";
        };
        minecraft_bedrock = {
          type = "udp";
          local_addr = "10.0.1.13:19132";
        };
      };
    };
  };
}
