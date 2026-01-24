{
  config,
  pkgs,
  ...
}:
let
  name = "frp";
  id = 131;
in
{
  sops.secrets."frp-token" = { };

  sops.templates."frpc.toml" = {
    owner = config.users.users."container-${name}".name;
    group = config.users.users.containers.group;

    content = # toml
      ''
        serverAddr = "87.106.25.93"
        serverPort = 2333

        auth.method = "token"
        auth.token = "${config.sops.placeholder."frp-token"}"

        [[proxies]]
        name = "nginx_http"
        type = "tcp"
        localIP = "10.0.1.6"
        localPort = 81
        remotePort = 80
        transport.proxyProtocolVersion = "v2"

        [[proxies]]
        name = "nginx_https"
        type = "tcp"
        localIP = "10.0.1.6"
        localPort = 4443
        remotePort = 443
        transport.proxyProtocolVersion = "v2"

        [[proxies]]
        name = "minecraft_java"
        type = "tcp"
        localIP = "10.0.1.13"
        localPort = 25565
        remotePort = 25565
        transport.proxyProtocolVersion = "v2"

        [[proxies]]
        name = "minecraft_bedrock"
        type = "udp"
        localIP = "10.0.1.13"
        localPort = 19132
        remotePort = 19132
        # transport.proxyProtocolVersion = "v2"
      '';
  };

  nerdctl-containers.${name} = {
    inherit id;

    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";
      config = {
        entrypoint = [ "${pkgs.frp}/bin/frpc" ];
        cmd = [
          "--strict_config"
          "-c"
          "/config/frpc.toml"
        ];
      };
    };

    volumes = [
      {
        hostPath = config.sops.templates."frpc.toml".path;
        containerPath = "/config/frpc.toml";
        readOnly = true;
      }
    ];
  };
}
