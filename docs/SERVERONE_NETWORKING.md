# serverone firewall and routing

The nftables ruleset has several owners. Do not use `nft flush ruleset`:

| Owner | Rules |
| --- | --- |
| `nftables.service` | NixOS host input and reverse-path filtering, forwarding, `inet serverone-routing` conntrack marks and source NAT |
| CNI `portmap` | `cni_hostport` DNAT and localhost/hairpin masquerading; mappings are installed and removed with the container |
| `tailscaled` | Native nftables input/forwarding, anti-spoofing and Tailscale marks. Subnet-route SNAT stays disabled |
| `polpetta-raw-firewall.service` | `inet` and `bridge` `polpetta_raw` tables; endpoint ACLs apply after DNAT and also to bridge peers |
| `qbittorrent-egress.service` | `ip qbittorrent_egress` kill switch and qBittorrent source-policy route, independent of WireGuard availability |

NixOS still uses existing host port/interface declarations. It also trusts
`tailscale0` for host input, since an accept in Tailscale's separate base chain
cannot override the host firewall. Forwarding permits established/related traffic,
DNAT, LAN and WireGuard access to the bridge, bridge egress, and Tailscale routing.
Unrelated new forwarding outside those paths is not allowed. The independent raw
endpoint drops and torrent kill switch still take precedence.

Container source NAT is in the host-owned chain, not the CNI bridge plugin:
qBittorrent's WireGuard exception must be in the same chain as the general bridge
masquerade. Tailscale traffic leaving `enp2s0` is masqueraded for exit-node use
(IPv4 and IPv6); traffic to container IPs keeps the original tailnet source.
WireGuard return flows restore conntrack bit `0x1` on the bridge ingress without
replacing other mark bits. The vps-proxy configuration is unchanged.

The serverone nerdctl build checks the native CNI table for published-port
collisions alongside local socket checks. `nerdctl-bridge` is labeled as its
rootful default network so a normal `nerdctl run` does not create the legacy CNI
bridge. If a previously generated default network or any hand-managed CNI
conflists exist, inventory them before cutover. They are not migrated here.

## Cutover and rollback notes

Build and stage the desired generation, then use a maintenance reboot with
console access for the first cutover (and for a rollback to iptables). A live
firewall reload does not migrate existing conntrack entries, old CNI rules or
already running container network sandboxes. Do not try to fix this by flushing
all firewall tables: a reboot clears old in-kernel state and lets each service
install its own rules again. Verify all managed containers recreated their CNI
networks and published ports.

After boot, inspect `nft list ruleset`, `ip rule`, and `ip route show table 51820`.
Check LAN and tailnet name resolution and ingress, a published TCP and UDP port,
tailnet subnet and IPv4/IPv6 exit-node connectivity, public edge return traffic,
and that qBittorrent cannot fall back to the LAN when WireGuard is unavailable.
The `raw-firewall` VM check exercises the same nft host policy and real CNI
portmap with simulated interfaces, not logged-in Tailscale or WireGuard peers.
