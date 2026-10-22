# WireGuard tunnel endpoint on the vps: serverone initiates from behind its
# NAT, the vps only listens. Public traffic forwarded to serverone (edge
# forwards below, from commit "edge: DNAT public raw ports") keeps its real
# source address — no SNAT — so replies must be policy-routed back into the
# tunnel on serverone (see system/hosts/serverone/wireguard.nix).
{
  config,
  lib,
  flakeInputs,
  ...
}:
let
  # serverone's wireguard public key from the secrets repo, same pattern as
  # the authorized ssh keys. The trailing newline is stripped: wg rejects
  # keys with trailing whitespace.
  serveronePublicKey = lib.removeSuffix "\n" (
    builtins.readFile "${flakeInputs.secrets-repo}/public_keys/wireguard/serverone.pub"
  );
in
{
  sops.secrets.wireguard-key = { };

  # Public traffic is DNAT'd into the tunnel (FORWARD, not INPUT); without
  # forwarding the vps is a dead end.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.firewall = {
    # Un-translated replies arrive from the tunnel carrying the vps's own
    # public address as source (conntrack reverses the DNAT before the route
    # check); strict reverse-path filtering would drop them as martians.
    checkReversePath = "loose";

    allowedUDPPorts = [
      # The tunnel itself.
      51820
    ];

    # The tunnel path MTU is 1420 (wireguard encapsulation overhead), while
    # TCP peers negotiate MSS against the 1500-byte WAN. Without clamping,
    # bulk transfers stall on full-size packets. Outbound clamps to the
    # interface PMTU; inbound (tunnel -> WAN) needs the explicit value, since
    # the PMTU of the output route is the unconstrained 1500.
    extraCommands = # sh
      ''
        iptables -w -t mangle -C FORWARD -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null ||
          iptables -w -t mangle -A FORWARD -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
        iptables -w -t mangle -C FORWARD -i wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360 2>/dev/null ||
          iptables -w -t mangle -A FORWARD -i wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360
      '';
    extraStopCommands = # sh
      ''
        iptables -w -t mangle -D FORWARD -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
        iptables -w -t mangle -D FORWARD -i wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360 2>/dev/null || true
      '';
  };

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.1/24" ];
    listenPort = 51820;
    mtu = 1420;
    privateKeyFile = config.sops.secrets.wireguard-key.path;
    peers = [
      {
        publicKey = serveronePublicKey;
        # The tunnel subnet plus serverone's container bridge: edge DNAT
        # rewrites public ports straight to container IPs, so the tunnel must
        # carry and route those destinations.
        allowedIPs = [
          "10.100.0.2/32"
          "10.0.1.0/24"
        ];
        # serverone initiates and roams (its WAN IP may change): no endpoint,
        # no keepalive — the peer address is learned from authenticated
        # packets.
      }
    ];
  };
}
