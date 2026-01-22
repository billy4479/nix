{ config, ... }:
{
  sops.secrets.rathole-credentials = { };

  services.rathole = {
    enable = true;
    role = "server";

    credentialsFile = config.sops.secrets.rathole-credentials.path;

    settings.server = {
      bind_addr = "0.0.0.0:2333";
      transport = {
        type = "noise";
        # noise.local_private_key from credentialsFile
      };

      services = {
        nginx_http = {
          type = "tcp";
          bind_addr = "0.0.0.0:80";
        };
        nginx_https = {
          type = "tcp";
          bind_addr = "0.0.0.0:443";
        };
        minecraft_java = {
          type = "tcp";
          bind_addr = "0.0.0.0:25565";
        };
        minecraft_bedrock = {
          type = "udp";
          bind_addr = "0.0.0.0:19132";
        };
      };
    };
  };
}
