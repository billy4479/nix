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
    owner = "container-${toString config.nerdctl-containers.${name}.uid}";
    group = config.users.users.containers.group;

    content = # toml
      ''
        serverAddr = "87.106.25.93"
        serverPort = 2333
        udpPacketSize = 4096

        auth.method = "token"
        auth.token = "${config.sops.placeholder."frp-token"}"

        [[proxies]]
        name = "nginx_http"
        type = "tcp"
        localIP = "10.0.1.6"
        localPort = 81
        remotePort = 80
        transport.proxyProtocolVersion = "v2"

        # nginx_https: 443 on the vps is the SNI demuxer (sni-demux.nix), which
        # already writes a PROXY protocol header that transits frps/frpc
        # byte-for-byte; a frpc-generated header (src=127.0.0.1) here would
        # double-stack and break real client IPs. nginx_http above keeps the
        # frps-generated PPv2.
        [[proxies]]
        name = "nginx_https"
        type = "tcp"
        localIP = "10.0.1.6"
        localPort = 4443
        remotePort = 8444

        [[proxies]]
        name = "minecraft_java"
        type = "tcp"
        localIP = "10.0.1.13"
        localPort = 25565
        remotePort = 25565
        # transport.proxyProtocolVersion = "v2"
        # TODO: This in theory should be supported with mods, in practice I think we can ignore this
        # https://modrinth.com/mod/proxy-protocol-support

        [[proxies]]
        name = "minecraft_bedrock"
        type = "udp"
        localIP = "10.0.1.13"
        localPort = 19132
        remotePort = 19132
        # transport.proxyProtocolVersion = "v2"

        [[proxies]]
        name = "lunamultiplayer"
        type = "udp"
        localIP = "10.0.1.20"
        localPort = 8800
        remotePort = 8800
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

    dependsOn = [
      "nginx"
      "mc-runner"
      "lunamultiplayer-server"
    ];
  };
}
