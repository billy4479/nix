{
  config,
  flakeInputs,
  lib,
  pkgs,
  ...
}:
let
  wgInterface = "wg-vps";

  # WireGuard tunnel IPs
  serveroneWgAddr = "10.100.0.2/30";
  vpsWgAddr = "10.100.0.1";

  # VPS public IP and WireGuard port
  vpsPublicAddr = "87.106.25.93";
  vpsWgPort = 51820;

  # Routing table and fwmark for policy routing.
  # Ensures reply traffic for connections arriving via WireGuard
  # goes back through the tunnel instead of the default gateway.
  rtTable = 100;
  fwMark = 1;

  # Containers whose outbound internet traffic should be routed through
  # the WireGuard tunnel (e.g. for torrenting via the VPS).
  # Traffic to local subnets is excluded so that web UIs and
  # container-to-container communication stay local.
  wgRoutedContainers = [
    "10.0.1.5" # qbittorrent
  ];

  ip = "${pkgs.iproute2}/bin/ip";
  iptables = "${pkgs.iptables}/bin/iptables";

  # Mark all outbound traffic from selected containers, then exempt local subnets.
  # Order matters: mark first, then clear for private destinations.
  markRules = lib.concatMapStringsSep "\n" (
    addr:
    # sh
    ''
      ${iptables} -t mangle -A PREROUTING -s ${addr} -j MARK --set-mark ${toString fwMark}
      ${iptables} -t mangle -A PREROUTING -s ${addr} -d 10.0.0.0/8 -j MARK --set-mark 0
      ${iptables} -t mangle -A PREROUTING -s ${addr} -d 192.168.0.0/16 -j MARK --set-mark 0
    '') wgRoutedContainers;

  unmarkRules = lib.concatMapStringsSep "\n" (
    addr:
    # sh
    ''
      ${iptables} -t mangle -D PREROUTING -s ${addr} -j MARK --set-mark ${toString fwMark} || true
      ${iptables} -t mangle -D PREROUTING -s ${addr} -d 10.0.0.0/8 -j MARK --set-mark 0 || true
      ${iptables} -t mangle -D PREROUTING -s ${addr} -d 192.168.0.0/16 -j MARK --set-mark 0 || true
    '') wgRoutedContainers;
in
{
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  sops.secrets."wireguard-key" = { };

  networking.wireguard.interfaces.${wgInterface} = {
    ips = [ serveroneWgAddr ];
    privateKeyFile = config.sops.secrets."wireguard-key".path;

    peers = [
      {
        publicKey = builtins.readFile "${flakeInputs.secrets-repo}/public_keys/wireguard/vps-proxy.pub";
        endpoint = "${vpsPublicAddr}:${toString vpsWgPort}";
        allowedIPs = [ "0.0.0.0/0" ];
        persistentKeepalive = 25;
      }
    ];

    postSetup = # sh
      ''
        # Policy routing: connections arriving via the WireGuard tunnel get a
        # connmark. When the reply leaves through the container bridge, the
        # connmark is restored as a packet mark, which triggers the policy
        # routing table so the reply goes back through the tunnel.

        # On incoming packets from WireGuard, save the mark into conntrack
        ${iptables} -t mangle -A PREROUTING -i ${wgInterface} -j CONNMARK --set-mark ${toString fwMark}

        # On all other incoming packets, restore connmark → fwmark so replies
        # to WireGuard-originated connections get the right mark
        ${iptables} -t mangle -A PREROUTING -m connmark --mark ${toString fwMark} -j CONNMARK --restore-mark

        # Route outbound internet traffic from selected containers through WireGuard.
        # Local subnet traffic is exempted so web UIs stay accessible directly.
        ${markRules}

        # SNAT outbound container traffic leaving via WireGuard
        ${iptables} -t nat -A POSTROUTING -o ${wgInterface} -s 10.0.1.0/24 -j MASQUERADE

        # Routing table that sends marked traffic via WireGuard
        ${ip} route replace default via ${vpsWgAddr} dev ${wgInterface} table ${toString rtTable}
        ${ip} rule add fwmark ${toString fwMark} table ${toString rtTable} priority 100 || true
      '';

    postShutdown = # sh
      ''
        ${iptables} -t mangle -D PREROUTING -i ${wgInterface} -j CONNMARK --set-mark ${toString fwMark} || true
        ${iptables} -t mangle -D PREROUTING -m connmark --mark ${toString fwMark} -j CONNMARK --restore-mark || true
        ${unmarkRules}
        ${iptables} -t nat -D POSTROUTING -o ${wgInterface} -s 10.0.1.0/24 -j MASQUERADE || true
        ${ip} rule del fwmark ${toString fwMark} table ${toString rtTable} || true
        ${ip} route flush table ${toString rtTable} || true
      '';
  };
}
