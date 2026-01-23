{
  config,
  pkgs,
  ...
}:
let
  name = "gost";
  id = 20;
in
{
  sops.secrets."gost-credentials/username" = { };
  sops.secrets."gost-credentials/password" = { };

  sops.templates."gost.yaml" = {
    owner = config.users.users."container-${name}".name;
    group = config.users.users.containers.group;
    content = # yaml
      ''
        services:
        - name: nginx-http
          addr: :80
          handler:
            type: rtcp
          listener:
            type: rtcp
            chain: relay-chain
          forwarder:
            nodes:
            - addr: 10.0.1.6:80
          metadata:
              proxyProtocol: 1

        - name: nginx-https
          addr: :443
          handler:
            type: rtcp
          listener:
            type: rtcp
            chain: relay-chain
          forwarder:
            nodes:
            - addr: 10.0.1.6:443
          metadata:
              proxyProtocol: 1

        - name: minecraft-java
          addr: :25565
          handler:
            type: rtcp
          listener:
            type: rtcp
            chain: relay-chain
          forwarder:
            nodes:
            - addr: 10.0.1.13:25565
          metadata:
              proxyProtocol: 1

        - name: minecraft-bedrock
          addr: :19132
          handler:
            type: rudp
          listener:
            type: rudp
            chain: relay-chain
          forwarder:
            nodes:
            - addr: 10.0.1.13:19132
          metadata:
              proxyProtocol: 1

        chains:
        - name: relay-chain
          hops:
          - name: vps-relay
            addr: 87.106.25.93:2333
            node:
              auth:
                username: "${config.sops.placeholder."gost-credentials/username"}"
                password: "${config.sops.placeholder."gost-credentials/password"}"
      '';
  };

  nerdctl-containers.${name} = {
    inherit id;

    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";
      config = {
        entrypoint = [ "${pkgs.gost}/bin/gost" ];
        cmd = [
          "-C"
          "/config/gost.yaml"
        ];
      };
    };

    volumes = [
      {
        hostPath = config.sops.templates."gost.yaml".path;
        containerPath = "/config/gost.yaml";
        readOnly = true;
      }
    ];
  };
}
