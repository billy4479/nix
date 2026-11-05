# The serverone side of the public edge tunnel: serverone initiates (only
# outbound connections, so its NAT needs no port forwarding) and keeps the
# mapping alive. The vps forwards public traffic into the tunnel with the
# source address preserved, so this side must send replies back through the
# tunnel while everything else keeps using the normal uplink — that is what
# the conntrack mark + policy rule below do.
{
  config,
  lib,
  flakeInputs,
  ...
}:
let
  vpsPublicKey = lib.removeSuffix "\n" (
    builtins.readFile "${flakeInputs.secrets-repo}/public_keys/wireguard/vps-proxy.pub"
  );

  vpsEndpoint = "87.106.25.93:51820";

  # Routing table and fwmark for "this flow must return via the tunnel".
  # Packets arriving on wg0 get their conntrack entry marked; replies
  # (forwarded from the containers) restore the mark into the packet and the
  # policy rule routes them into the tunnel table. Ordinary container egress
  # has no ctmark and keeps the main table.
  wgTable = 51820;
  wgMark = "0x1";
in
{
  sops.secrets.wireguard-key = {
    # Same startup-only consumer concern as the vps side: restart the
    # interface when the key rotates or the tunnel breaks silently.
    restartUnits = [ "wireguard-wg0.service" ];
  };

  # headscale's module declares this too; mkDefault keeps the two compatible
  # while still forwarding if headscale ever moves off the host.
  boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkDefault 1;

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.2/24" ];
    mtu = 1420;
    privateKeyFile = config.sops.secrets.wireguard-key.path;
    # Assigning 10.100.0.2/24 routes the tunnel subnet via wg0 in the main
    # table (needed for replies to vps-originated connections). Everything
    # else in AllowedIPs is a filter only: 0.0.0.0/0 must not install a
    # default route, the policy rule decides what rides the tunnel.
    allowedIPsAsRoutes = false;
    peers = [
      {
        publicKey = vpsPublicKey;
        # Cryptokey routing filter, not routes: packets arriving through the
        # tunnel carry arbitrary public client addresses.
        allowedIPs = [ "0.0.0.0/0" ];
        endpoint = vpsEndpoint;
        # Keep the NAT mapping alive through the home router.
        persistentKeepalive = 25;
      }
    ];
    postSetup = # sh
      ''
        # Default route in the tunnel table for policy-routed traffic.
        ip route show table ${toString wgTable} | grep -q default ||
          ip route add default dev wg0 table ${toString wgTable}
        # Priority between tailscale's rules (52xx) and main (32766).
        ip rule show | grep -q "fwmark ${wgMark}" ||
          ip rule add fwmark ${wgMark} table ${toString wgTable} priority 10000
      '';
  };

  # The tailscale rules in containers.nix follow the same idempotent
  # pattern; types.lines concatenates both definitions.
  networking.firewall.extraCommands =
    lib.mkAfter # sh
      ''
        iptables -w -t mangle -C PREROUTING -i wg0 -j CONNMARK --set-xmark ${wgMark}/${wgMark} 2>/dev/null ||
          iptables -w -t mangle -A PREROUTING -i wg0 -j CONNMARK --set-xmark ${wgMark}/${wgMark}
        iptables -w -t mangle -C PREROUTING -i nerdctl0 -j CONNMARK --restore-mark --nfmask 0x1 --ctmask 0x1 2>/dev/null ||
          iptables -w -t mangle -A PREROUTING -i nerdctl0 -j CONNMARK --restore-mark --nfmask 0x1 --ctmask 0x1
        iptables -w -C FORWARD -i wg0 -o nerdctl0 -d 10.0.1.0/24 -j ACCEPT 2>/dev/null ||
          iptables -w -I FORWARD 1 -i wg0 -o nerdctl0 -d 10.0.1.0/24 -j ACCEPT
        iptables -w -C FORWARD -i nerdctl0 -o wg0 -s 10.0.1.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null ||
          iptables -w -I FORWARD 1 -i nerdctl0 -o wg0 -s 10.0.1.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      '';
  networking.firewall.extraStopCommands =
    lib.mkAfter # sh
      ''
        iptables -w -t mangle -D PREROUTING -i wg0 -j CONNMARK --set-xmark ${wgMark}/${wgMark} 2>/dev/null || true
        iptables -w -t mangle -D PREROUTING -i nerdctl0 -j CONNMARK --restore-mark --nfmask 0x1 --ctmask 0x1 2>/dev/null || true
        iptables -w -D FORWARD -i wg0 -o nerdctl0 -d 10.0.1.0/24 -j ACCEPT 2>/dev/null || true
        iptables -w -D FORWARD -i nerdctl0 -o wg0 -s 10.0.1.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
      '';
}
