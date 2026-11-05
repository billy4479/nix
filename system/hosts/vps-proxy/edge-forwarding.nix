# Keep forwarding outside firewall.service: on a NixOS switch that service
# reloads with the new generation's cleanup script. A separate, restarting
# unit instead runs the old ExecStopPost before replacing or removing its rules.
{
  lib,
  pkgs,
  publicIp,
  forwards,
}:
let
  chain = "POLPETTA-EDGE";
  rules = lib.concatMapStrings (f: ''
    iptables -w -t nat -A ${chain} -p ${f.proto} --dport ${toString f.port} -j DNAT --to-destination ${f.target}:${toString f.targetPort}
  '') forwards;
in
{
  description = "Forward public edge ports through WireGuard";
  wantedBy = [ "multi-user.target" ];
  requires = [ "wireguard-wg0.service" ];
  after = [
    "firewall.service"
    "wireguard-wg0.service"
  ];
  partOf = [ "wireguard-wg0.service" ];
  path = [ pkgs.iptables ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };
  script = # sh
    ''
      iptables -w -t nat -N ${chain}
      ${rules}
      iptables -w -t nat -A PREROUTING -d ${publicIp} -j ${chain}

      # Clamp both directions across the 1420-byte tunnel. The WAN-bound
      # route has MTU 1500, so its MSS needs an explicit limit.
      iptables -w -t mangle -A FORWARD -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
      iptables -w -t mangle -A FORWARD -i wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360
    '';
  # ExecStopPost also cleans up if setup fails partway through.
  postStop = # sh
    ''
      iptables -w -t nat -D PREROUTING -d ${publicIp} -j ${chain} 2>/dev/null || true
      iptables -w -t nat -F ${chain} 2>/dev/null || true
      iptables -w -t nat -X ${chain} 2>/dev/null || true
      iptables -w -t mangle -D FORWARD -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
      iptables -w -t mangle -D FORWARD -i wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360 2>/dev/null || true
    '';
}
