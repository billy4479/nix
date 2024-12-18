{ pkgs, lib, config, ... }:
let
  eth = "enp2s0";
in
{
  sops.secrets.wireguard_key = { };

  networking = {
    wireguard.interfaces.wg0 =
      let
        iptables = "${pkgs.iptables}/bin/iptables";
      in
      {
        ips = [
          "10.0.0.1/32"
          "10.0.1.1/24"
        ];
        listenPort = 51820;

        # Thanks ChatGPT!
        # Allow traffic between WireGuard and the host/container network
        # Enable NAT for full-tunnel clients
        postSetup = ''
          ${iptables} -A FORWARD -i wg0 -j ACCEPT; \
          ${iptables} -A FORWARD -o wg0 -j ACCEPT; \
          ${iptables} -t nat -A POSTROUTING -o ${eth} -s 10.0.254.0/24 -j MASQUERADE
        '';
        postShutdown = ''
          ${iptables} -D FORWARD -i wg0 -j ACCEPT; \
          ${iptables} -D FORWARD -o wg0 -j ACCEPT; \
          ${iptables} -t nat -D POSTROUTING -o ${eth} -s 10.0.254.0/24 -j MASQUERADE
        '';

        privateKeyFile = config.sops.secrets.wireguard_key.path;

        peers =
          let
            keyPath = ../../../secrets/public_keys/wireguard;
            mapPeers =
              peers:
              lib.lists.flatten (
                map (peer: [
                  {
                    publicKey = builtins.readFile (keyPath + "/${peer.name}-split.pub");
                    allowedIPs = [ "10.0.253.${builtins.toString peer.ip}/32" ];
                  }
                  {
                    publicKey = builtins.readFile (keyPath + "/${peer.name}-full.pub");
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
