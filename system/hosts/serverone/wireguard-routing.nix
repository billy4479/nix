{ pkgs, ... }:
let
  ip = "${pkgs.iproute2}/bin/ip";
  iptables = "${pkgs.iptables}/bin/iptables";

  containerIf = "nerdctl0";
  containerCidr = "10.0.1.0/24";
  wgGateway = "10.0.1.17";
  mark = "0x1";
  table = "100";
in
{
  boot.kernelModules = [ "br_netfilter" ];
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 2;
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.bridge.bridge-nf-call-arptables" = 1;
  };

  systemd.services.wireguard-routing = {
    description = "Policy routing for WireGuard container";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "all-containers.target"
    ];
    wants = [
      "network-online.target"
      "all-containers.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for i in $(seq 1 30); do
        ${ip} link show ${containerIf} >/dev/null 2>&1 && break
        sleep 1
      done

      if ! ${ip} link show ${containerIf} >/dev/null 2>&1; then
        echo "${containerIf} not found, skipping policy routing"
        exit 0
      fi

      ensure_mangle_rule() {
        ${iptables} -t mangle -C "$@" 2>/dev/null || ${iptables} -t mangle -A "$@"
      }

      ensure_nat_rule() {
        ${iptables} -t nat -C "$@" 2>/dev/null || ${iptables} -t nat -I "$@"
      }

      ensure_filter_rule() {
        ${iptables} -C "$@" 2>/dev/null || ${iptables} -A "$@"
      }

      ensure_mangle_rule PREROUTING -i ${containerIf} -s ! ${containerCidr} -d ${containerCidr} \
        -m conntrack --ctstate NEW -j CONNMARK --set-mark ${mark}
      ensure_mangle_rule PREROUTING -i ${containerIf} -m connmark --mark ${mark} -j CONNMARK --restore-mark

      ensure_nat_rule POSTROUTING -m connmark --mark ${mark} -j RETURN

      ensure_filter_rule FORWARD -i ${containerIf} -o ${containerIf} -m connmark --mark ${mark} -j ACCEPT

      ${ip} rule add pref 100 fwmark ${mark} table ${table} 2>/dev/null || true
      ${ip} route replace default via ${wgGateway} dev ${containerIf} table ${table}
    '';
  };
}
