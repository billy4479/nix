{ qbtIp, wgMark }:
{
  networking.nftables = {
    enable = true;
    # CNI, Tailscale and the two independent policy units own their tables.
    flushRuleset = false;

    tables.serverone-routing = {
      family = "inet";
      content = # nftables
        ''
          chain prerouting {
            # After Tailscale's mangle hook, before NixOS reverse-path filtering.
            type filter hook prerouting priority mangle + 5; policy accept;
            iifname "wg0" ct mark set ct mark | ${wgMark}
            iifname "nerdctl0" ct mark & ${wgMark} != 0 meta mark set meta mark | ${wgMark}
            iifname "nerdctl0" ct mark & ${wgMark} == 0 meta mark set meta mark & 0xfffffffe
          }

          chain postrouting {
            type nat hook postrouting priority srcnat + 5; policy accept;
            # Preserve the torrent client's source on the tunnel. This must be
            # in the same chain as bridge MASQ; accept in a separate NAT chain
            # would not prevent later hooks from masquerading the packet.
            ip saddr ${qbtIp} oifname "wg0" return
            # Replaces CNI ipMasq for the IPv4-only bridge. CNI portmap still
            # owns localhost and hairpin MASQ (at srcnat).
            ip saddr 10.0.1.0/24 ip daddr != { 10.0.1.0/24, 224.0.0.0/4 } masquerade

            # --snat-subnet-routes=false preserves source IPs for container
            # ACLs and WhoIs. Only traffic exiting the LAN uplink needs SNAT.
            oifname "enp2s0" ip saddr 100.64.0.0/10 masquerade
            oifname "enp2s0" ip6 saddr fd7a:115c:a1e0::/48 masquerade
          }
        '';
    };
  };

  networking.firewall = {
    # Tailscale's independent nft INPUT accept cannot bypass nixos-fw.
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
    filterForward = true;
    # Established/related and published DNAT ports are handled by nixos-fw.
    # The raw-port and torrent guard drops still apply independently.
    extraForwardRules = # nftables
      ''
        iifname "nerdctl0" ip saddr 10.0.1.0/24 accept
        iifname { "wg0", "enp2s0" } oifname "nerdctl0" ip daddr 10.0.1.0/24 accept
        iifname "tailscale0" accept
        oifname "tailscale0" accept
      '';
  };
}
