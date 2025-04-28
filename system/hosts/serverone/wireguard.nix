{
  pkgs,
  lib,
  config,
  ...
}:
let
  eth = "enp2s0";
  podmanInterface = "podman0";
in
{
  sops.secrets.wireguard_key = { };

  networking = {
    wireguard.interfaces.wg0 =
      let
        iptables = "${pkgs.iptables}/bin/iptables";
        ip = "${pkgs.iproute2}/bin/ip";
      in
      {
        ips = [
          "10.0.0.1/32"
          "10.0.1.1/24"
        ];
        listenPort = 51820;

        # Thanks ChatGPT!
        # https://chatgpt.com/share/67696fe5-3568-8013-b942-8c5af7df2219
        postSetup = lib.strings.concatStringsSep "\n" [
          # *** Full-tunnel clients ***

          # Make sure that full-tunnel clients can access ips NOT in 10.0.0.0/16 normally
          "${iptables} -t nat -A POSTROUTING -s 10.0.254.0/24 ! -d 10.0.0.0/16 -j MASQUERADE"

          # This is for full-tunnel clients to allow traffic to go through the wg0 interface
          # Allow connections to go out from wg0 to the internet
          "${iptables} -A FORWARD -i wg0 -o ${eth} -s 10.0.254.0/24 -j ACCEPT"
          # Allow responses to come back
          "${iptables} -A FORWARD -i ${eth} -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT"

          # *** General configuration ***

          # Enable NAT for traffic from WireGuard clients to the Podman containers
          "${iptables} -t nat -A POSTROUTING -s 10.0.253.0/24 -d 10.0.1.0/24 -j MASQUERADE"
          "${iptables} -t nat -A POSTROUTING -s 10.0.254.0/24 -d 10.0.1.0/24 -j MASQUERADE"

          # Allow forwarding from WireGuard to Podman
          "${iptables} -A FORWARD -i wg0 -o ${podmanInterface} -s 10.0.253.0/24 -d 10.0.1.0/24 -j ACCEPT"
          "${iptables} -A FORWARD -i wg0 -o ${podmanInterface} -s 10.0.254.0/24 -d 10.0.1.0/24 -j ACCEPT"

          # Allow forwarding from Podman to WireGuard
          "${iptables} -A FORWARD -i ${podmanInterface} -o wg0 -s 10.0.1.0/24 -d 10.0.253.0/24 -j ACCEPT"
          "${iptables} -A FORWARD -i ${podmanInterface} -o wg0 -s 10.0.1.0/24 -d 10.0.254.0/24 -j ACCEPT"

          "${iptables} -A INPUT -i wg0 -j ACCEPT"
          "${iptables} -A FORWARD -i wg0 -j ACCEPT"

          # IP routing
          # Not sure if this is the proper way to do this but it seems to be working
          "${ip} route del 10.0.1.0/24 dev wg0 || true"
          "${ip} route add 10.0.1.0/24 dev ${podmanInterface} || true"
        ];

        # Undo the above commands (mostly just replace add with del and -A with -D)
        postShutdown = lib.strings.concatStringsSep "\n" [
          "${iptables} -t nat -D POSTROUTING -s 10.0.254.0/24 ! -d 10.0.0.0/16 -j MASQUERADE"

          "${iptables} -D FORWARD -i wg0 -o ${eth} -s 10.0.254.0/24 -j ACCEPT"
          "${iptables} -D FORWARD -i ${eth} -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT"

          "${iptables} -t nat -D POSTROUTING -s 10.0.253.0/24 -d 10.0.1.0/24 -j MASQUERADE"
          "${iptables} -t nat -D POSTROUTING -s 10.0.254.0/24 -d 10.0.1.0/24 -j MASQUERADE"

          "${iptables} -D FORWARD -i wg0 -o ${podmanInterface} -s 10.0.253.0/24 -d 10.0.1.0/24 -j ACCEPT"
          "${iptables} -D FORWARD -i wg0 -o ${podmanInterface} -s 10.0.254.0/24 -d 10.0.1.0/24 -j ACCEPT"

          "${iptables} -D FORWARD -i ${podmanInterface} -o wg0 -s 10.0.1.0/24 -d 10.0.253.0/24 -j ACCEPT"
          "${iptables} -D FORWARD -i ${podmanInterface} -o wg0 -s 10.0.1.0/24 -d 10.0.254.0/24 -j ACCEPT"

          "${ip} route del 10.0.1.0/24 dev ${podmanInterface}"
        ];

        privateKeyFile = config.sops.secrets.wireguard_key.path;

        peers =
          let
            keyPath = ../../../secrets/public_keys/wireguard;
            mapPeers =
              peers:
              lib.lists.flatten (
                map (peer: [
                  {
                    publicKey = builtins.readFile (keyPath + "/${peer.name}/wg0-split-loc.pub");
                    allowedIPs = [ "10.0.251.${builtins.toString peer.ip}/32" ];
                  }
                  {
                    publicKey = builtins.readFile (keyPath + "/${peer.name}/wg1-split-pub.pub");
                    allowedIPs = [ "10.0.252.${builtins.toString peer.ip}/32" ];
                  }
                  {
                    publicKey = builtins.readFile (keyPath + "/${peer.name}/wg2-full-loc.pub");
                    allowedIPs = [ "10.0.253.${builtins.toString peer.ip}/32" ];
                  }
                  {
                    publicKey = builtins.readFile (keyPath + "/${peer.name}/wg3-full-pub.pub");
                    allowedIPs = [ "10.0.254.${builtins.toString peer.ip}/32" ];
                  }
                ]) peers
              );
          in
          mapPeers [
            {
              name = "computerone";
              ip = 1;
            }
            {
              name = "portatilo";
              ip = 2;
            }
            {
              name = "nord";
              ip = 10;
            }
          ];
      };

    nat = {
      enable = true;
      externalInterface = eth;
      internalInterfaces = [ "wg0" ];
    };

    firewall = {
      allowedUDPPorts = [ 51820 ];
    };
  };
}
