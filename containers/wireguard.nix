{
  config,
  pkgs,
  ...
}:
let
  name = "wireguard";
  id = 17;
in
{
  sops.secrets."wireguard-serverone-private" = { };
  sops.secrets."wireguard-vps-public" = { };

  sops.templates."wg0.conf" = {
    owner = config.users.users."container-${name}".name;
    group = config.users.users.containers.group;
    content = ''
      [Interface]
      Address = 10.42.0.2/24
      PrivateKey = ${config.sops.placeholder."wireguard-serverone-private"}

      [Peer]
      PublicKey = ${config.sops.placeholder."wireguard-vps-public"}
      Endpoint = 87.106.25.93:51820
      AllowedIPs = 0.0.0.0/0
      PersistentKeepalive = 25
    '';
  };

  nerdctl-containers.${name} = {
    inherit id;
    runByUser = false;

    imageToBuild = pkgs.nix-snapshotter.buildImage {
      inherit name;
      tag = "nix-local";
      config = {
        entrypoint = [ "/bin/bash" ];
        cmd = [
          "-c"
          "wg-quick up /config/wg0.conf && tail -f /dev/null"
        ];
      };

      copyToRoot = with pkgs; [
        bash
        coreutils
        iproute2
        iptables
        wireguard-tools
      ];
    };

    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--device=/dev/net/tun"
      "--sysctl=net.ipv4.ip_forward=1"
      "--sysctl=net.ipv4.conf.all.rp_filter=2"
    ];

    volumes = [
      {
        hostPath = config.sops.templates."wg0.conf".path;
        containerPath = "/config/wg0.conf";
        readOnly = true;
      }
    ];
  };
}
