{ config, pkgs, ... }:
let
  wgName = "wg0";
  wgConf = config.sops.templates."wg0.conf".path;
  iptables = "${pkgs.iptables}/bin/iptables";
in
{
  networking.firewall = {
    allowedTCPPorts = [
      80
      443
      25565
    ];
    allowedUDPPorts = [
      19132
      3478
      51820
    ];
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 2;
  };

  sops.secrets."wireguard-vps-private" = { };
  sops.secrets."wireguard-serverone-public" = { };

  sops.templates."wg0.conf" = {
    content = ''
      [Interface]
      Address = 10.42.0.1/24
      ListenPort = 51820
      PrivateKey = ${config.sops.placeholder."wireguard-vps-private"}

      [Peer]
      PublicKey = ${config.sops.placeholder."wireguard-serverone-public"}
      AllowedIPs = 10.42.0.2/32, 10.0.1.0/24
    '';
  };

  systemd.services."wg-quick-${wgName}" = {
    description = "WireGuard ${wgName}";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.wireguard-tools}/bin/wg-quick up ${wgConf}";
      ExecStop = "${pkgs.wireguard-tools}/bin/wg-quick down ${wgConf}";
    };
  };

  systemd.services.wireguard-iptables = {
    description = "iptables rules for WireGuard forwarding";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "wg-quick-${wgName}.service"
    ];
    wants = [
      "network-online.target"
      "wg-quick-${wgName}.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ensure_nat_rule() {
        ${iptables} -t nat -C "$@" 2>/dev/null || ${iptables} -t nat -A "$@"
      }

      ensure_filter_rule() {
        ${iptables} -C "$@" 2>/dev/null || ${iptables} -A "$@"
      }

      ensure_nat_rule PREROUTING -p tcp --dport 80 -j DNAT --to-destination 10.0.1.6:80
      ensure_nat_rule PREROUTING -p tcp --dport 443 -j DNAT --to-destination 10.0.1.6:443
      ensure_nat_rule PREROUTING -p tcp --dport 25565 -j DNAT --to-destination 10.0.1.13:25565
      ensure_nat_rule PREROUTING -p udp --dport 19132 -j DNAT --to-destination 10.0.1.13:19132
      ensure_nat_rule PREROUTING -p udp --dport 3478 -j DNAT --to-destination 10.0.1.15:3478

      ensure_filter_rule FORWARD -o ${wgName} -p tcp --dport 80 -d 10.0.1.6 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
      ensure_filter_rule FORWARD -o ${wgName} -p tcp --dport 443 -d 10.0.1.6 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
      ensure_filter_rule FORWARD -o ${wgName} -p tcp --dport 25565 -d 10.0.1.13 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
      ensure_filter_rule FORWARD -o ${wgName} -p udp --dport 19132 -d 10.0.1.13 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
      ensure_filter_rule FORWARD -o ${wgName} -p udp --dport 3478 -d 10.0.1.15 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
      ensure_filter_rule FORWARD -i ${wgName} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    '';
  };
}
