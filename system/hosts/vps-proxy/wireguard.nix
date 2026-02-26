{
  config,
  flakeInputs,
  lib,
  pkgs,
  ...
}:
let
  wgInterface = "wg-serverone";
  wgPort = 51820;

  # WireGuard tunnel IPs
  vpsWgAddr = "10.100.0.1/30";
  serveroneWgAddr = "10.100.0.2";

  # Serverone's container subnet, reachable through the tunnel
  containerSubnet = "10.0.1.0/24";

  # Port forwarding rules.
  # Each entry maps a public-facing port on vps-proxy to an IP:port on
  # serverone's container network (reachable via the WireGuard tunnel).
  portForwards = [
    # Nginx
    {
      proto = "tcp";
      port = 80;
      toAddr = "10.0.1.6";
      toPort = 80;
    }
    {
      proto = "tcp";
      port = 443;
      toAddr = "10.0.1.6";
      toPort = 443;
    }

    # Minecraft
    {
      proto = "tcp";
      port = 25565;
      toAddr = "10.0.1.13";
      toPort = 25565;
    }
    {
      proto = "udp";
      port = 19132;
      toAddr = "10.0.1.13";
      toPort = 19132;
    }

    # STUN
    {
      proto = "udp";
      port = 3478;
      toAddr = "10.0.1.15";
      toPort = 3478;
    }

    # qBittorrent
    {
      proto = "tcp";
      port = 6881;
      toAddr = "10.0.1.5";
      toPort = 6881;
    }
    {
      proto = "udp";
      port = 6881;
      toAddr = "10.0.1.5";
      toPort = 6881;
    }
  ];

  iptables = "${pkgs.iptables}/bin/iptables";

  # Build iptables DNAT + FORWARD rules from the portForwards list
  dnatRules = lib.concatMapStringsSep "\n" (fwd: ''
    ${iptables} -t nat -A PREROUTING -p ${fwd.proto} --dport ${toString fwd.port} -j DNAT --to-destination ${fwd.toAddr}:${toString fwd.toPort}
    ${iptables} -A FORWARD -p ${fwd.proto} -d ${fwd.toAddr} --dport ${toString fwd.toPort} -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
  '') portForwards;

  undnatRules = lib.concatMapStringsSep "\n" (fwd: ''
    ${iptables} -t nat -D PREROUTING -p ${fwd.proto} --dport ${toString fwd.port} -j DNAT --to-destination ${fwd.toAddr}:${toString fwd.toPort} || true
    ${iptables} -D FORWARD -p ${fwd.proto} -d ${fwd.toAddr} --dport ${toString fwd.toPort} -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT || true
  '') portForwards;

  # Unique public-facing ports per protocol for the firewall
  tcpPorts = map (f: f.port) (builtins.filter (f: f.proto == "tcp") portForwards);
  udpPorts = map (f: f.port) (builtins.filter (f: f.proto == "udp") portForwards);
in
{
  networking.firewall = {
    allowedTCPPorts = tcpPorts;
    allowedUDPPorts = udpPorts ++ [ wgPort ];
  };

  sops.secrets."wireguard-key" = { };

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.wireguard.interfaces.${wgInterface} = {
    ips = [ vpsWgAddr ];
    listenPort = wgPort;
    privateKeyFile = config.sops.secrets."wireguard-key".path;

    peers = [
      {
        publicKey = builtins.readFile "${flakeInputs.secrets-repo}/public_keys/wireguard/serverone.pub";
        allowedIPs = [
          "${serveroneWgAddr}/32"
          containerSubnet
        ];
      }
    ];

    postSetup = ''
      # Allow forwarding for established/related connections back through the tunnel
      ${iptables} -A FORWARD -i ${wgInterface} -m state --state ESTABLISHED,RELATED -j ACCEPT
      ${iptables} -A FORWARD -o ${wgInterface} -m state --state ESTABLISHED,RELATED -j ACCEPT
      # Allow new outbound connections from the tunnel to the internet
      ${iptables} -A FORWARD -i ${wgInterface} -m state --state NEW -j ACCEPT
      # MASQUERADE outbound traffic from the tunnel so it exits with the VPS public IP
      ${iptables} -t nat -A POSTROUTING ! -o ${wgInterface} -s ${containerSubnet} -j MASQUERADE
      # DNAT rules for port forwarding
      ${dnatRules}
    '';
    postShutdown = ''
      ${iptables} -D FORWARD -i ${wgInterface} -m state --state ESTABLISHED,RELATED -j ACCEPT || true
      ${iptables} -D FORWARD -o ${wgInterface} -m state --state ESTABLISHED,RELATED -j ACCEPT || true
      ${iptables} -D FORWARD -i ${wgInterface} -m state --state NEW -j ACCEPT || true
      ${iptables} -t nat -D POSTROUTING ! -o ${wgInterface} -s ${containerSubnet} -j MASQUERADE || true
      ${undnatRules}
    '';
  };
}
