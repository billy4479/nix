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
    content = # yaml
      ''
        services:
          # Handles all TCP streams arriving via the tunnel
          - name: client-tcp
            addr: ":0"
            handler:
              type: rtcp
            listener:
              type: rtcp
              chain: to-server-tunnel
            forwarder:
              nodes:
                - name: nginx-http
                  addr: "10.0.1.6:80"
                  filter:
                    host: "http.local"

                - name: nginx-https
                  addr: "10.0.1.6:443"
                  filter:
                    host: "https.local"

                - name: mc-java-local
                  addr: "10.0.1.13:25565"
                  filter:
                    host: "mcjava.local"

          # Handles all UDP datagrams arriving via the tunnel
          - name: client-udp
            addr: ":0"
            handler:
              type: rudp
            listener:
              type: rudp
              chain: to-server-tunnel
            forwarder:
              nodes:
                - name: mc-bedrock-local
                  addr: "10.0.1.13:19132"
                  filter:
                    host: "mcbedrock.local"

        chains:
          - name: to-server-tunnel
            hops:
              - name: hop-0
                nodes:
                  - name: tunnel
                    addr: "87.106.25.93:2333"
                    connector:
                      type: tunnel
                      auth:
                        username: "${config.sops.placeholder."gost-credentials/username"}"
                        password: "${config.sops.placeholder."gost-credentials/password"}"
                      metadata:
                        tunnel.id: "4d21094e-b74c-4916-86c1-d9fa36ea677b"
                    dialer:
                      type: tcp
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
