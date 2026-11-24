# The serverone side of the public edge tunnel: serverone initiates (only
# outbound connections, so its NAT needs no port forwarding) and keeps the
# mapping alive. The vps forwards public traffic into the tunnel with the
# source address preserved, so this side must send replies back through the
# tunnel while everything else keeps using the normal uplink — that is what
# the conntrack mark + policy rule below do.
{
  config,
  lib,
  pkgs,
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
  # keeps the main table except for qBittorrent, routed by source below.
  wgTable = 51820;
  wgMark = "0x1";

  qbt = config.polpetta.services.qbittorrent;
  qbtIp = "10.0.1.${toString qbt.container.id}";
  qbtRule = "priority 10001 from ${qbtIp}/32 table ${toString wgTable}";
  qbtGuard =
    pkgs.writeText "qbittorrent-egress.nft" # nftables
      ''
        destroy table ip qbittorrent_egress
        table ip qbittorrent_egress {
          chain forward {
            type filter hook forward priority -10; policy accept;
            ip saddr ${qbtIp} oifname "tailscale0" ct direction reply tcp sport ${toString qbt.web.port} accept
            ip saddr ${qbtIp} oifname != { "wg0", "nerdctl0" } counter drop
          }
        }
      '';
in
{
  imports = [ (import ./firewall.nix { inherit qbtIp wgMark; }) ];

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
        ip rule show | grep -Fq '10000:' ||
          ip rule add fwmark ${wgMark}/${wgMark} table ${toString wgTable} priority 10000
      '';
  };

  # Keep the kill switch installed independently of wg0 (including while
  # its policy table has no route). Start the container only once protected.
  systemd.services.qbittorrent-egress = {
    description = "Route qBittorrent through WireGuard only";
    after = [ "nftables.service" ];
    requires = [ "nftables.service" ];
    path = [
      pkgs.iproute2
      pkgs.nftables
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = # sh
      ''
        nft -f ${qbtGuard}
        ip rule add ${qbtRule}
      '';
    postStop = # sh
      ''
        ip rule del ${qbtRule} || true
        nft destroy table ip qbittorrent_egress
      '';
  };
  systemd.services.nerdctl-qbittorrent = {
    after = [ "qbittorrent-egress.service" ];
    bindsTo = [ "qbittorrent-egress.service" ];
    partOf = [ "qbittorrent-egress.service" ];
  };

}
