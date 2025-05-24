{
  pkgs,
  lib,
  config,
  flakeInputs,
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

        # Not sure if this is the proper way to do this but it seems to be working
        postSetup = lib.strings.concatStringsSep "\n" [
          "${iptables} -A INPUT -i wg0 -j ACCEPT"
          "${iptables} -A FORWARD -i wg0 -j ACCEPT"

          # IP routing
          "${ip} route del 10.0.1.0/24 dev wg0 || true"
          "${ip} route add 10.0.1.0/24 dev ${podmanInterface} || true"
        ];

        # Undo the above commands (mostly just replace add with del and -A with -D)
        postShutdown = lib.strings.concatStringsSep "\n" [
          "${iptables} -D INPUT -i wg0 -j ACCEPT"
          "${iptables} -D FORWARD -i wg0 -j ACCEPT"

          "${ip} route del 10.0.1.0/24 dev ${podmanInterface}"
        ];

        privateKeyFile = config.sops.secrets.wireguard_key.path;

        peers =
          let
            keyPath = "${flakeInputs.secrets-repo}/public_keys/wireguard";
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
