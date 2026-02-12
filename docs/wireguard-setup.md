# WireGuard tunnel between vps-proxy and serverone

This document explains how the WireGuard-based setup replaces FRP and how traffic flows end-to-end. It also details the exact iptables and routing rules used on each host and why they exist.

## High-level goals

- Replace FRP with a WireGuard tunnel.
- Preserve the real client IP all the way to the application (no proxy protocol).
- Keep WireGuard on vps-proxy (host) and inside a container on serverone.

## Components and addresses

- vps-proxy: public edge VPS, WireGuard runs on the host.
- serverone: private host with containers on `nerdctl0` (10.0.1.0/24), WireGuard runs in a container.

WireGuard tunnel:

- vps-proxy WG address: `10.42.0.1/24`
- serverone WG address: `10.42.0.2/24`
- WG port: UDP `51820`

Container network on serverone:

- `nerdctl0` bridge: `10.0.1.0/24`
- WG container IP: `10.0.1.17`
- nginx container IP: `10.0.1.6`
- minecraft container IP: `10.0.1.13`
- headscale container IP: `10.0.1.15`

Public services handled by vps-proxy:

- TCP `80/443` -> nginx `10.0.1.6`
- TCP `25565` -> minecraft `10.0.1.13`
- UDP `19132` -> minecraft `10.0.1.13`
- UDP `3478` -> headscale STUN `10.0.1.15`

## Where the configuration lives

- vps-proxy WG + iptables: `system/hosts/vps-proxy/wireguard.nix`
- serverone WG container: `containers/wireguard.nix`
- serverone policy routing + iptables: `system/hosts/serverone/wireguard-routing.nix`
- nginx (no proxy protocol): `containers/nginx/config/nginx.conf` and `containers/nginx/config/snippets/headers.conf`

## Traffic flow (end-to-end)

1) Client connects to vps-proxy public IP on one of the service ports.
2) vps-proxy uses DNAT in the `nat` table PREROUTING chain to rewrite the destination to the serverone container IP.
3) vps-proxy forwards the packet out of the WireGuard interface (`wg0`) to the serverone host.
4) serverone host receives the packet on `wg0`, then routes it to the target container via `nerdctl0`.
5) The container receives the packet with the original client IP intact.
6) The container reply goes back to the serverone host. Conntrack marks the connection, and policy routing forces the reply to go back through the WG container gateway.
7) The reply exits serverone via the WG container, reaches vps-proxy, and conntrack reverses the DNAT so the reply goes back to the original client.

Because only DNAT is used on vps-proxy (no SNAT/MASQUERADE), the original client IP is preserved all the way to the application.

## vps-proxy details

### WireGuard configuration

- A systemd service runs `wg-quick up` using a sops-rendered `wg0.conf`.
- The peer for serverone allows the whole container subnet `10.0.1.0/24` to be routed across the tunnel.

### iptables rules (vps-proxy)

Rules are installed by `systemd.services.wireguard-iptables` using idempotent helpers so reboots do not duplicate rules.

#### DNAT rules (NAT PREROUTING)

```
iptables -t nat -A PREROUTING -p tcp --dport 80  -j DNAT --to-destination 10.0.1.6:80
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination 10.0.1.6:443
iptables -t nat -A PREROUTING -p tcp --dport 25565 -j DNAT --to-destination 10.0.1.13:25565
iptables -t nat -A PREROUTING -p udp --dport 19132 -j DNAT --to-destination 10.0.1.13:19132
iptables -t nat -A PREROUTING -p udp --dport 3478  -j DNAT --to-destination 10.0.1.15:3478
```

What these do:

- Rewrites the destination IP/port **before routing** so Linux routes the packet toward the WireGuard peer.
- The source IP remains unchanged. This is the critical piece that preserves the real client IP for the application.

#### FORWARD rules

```
iptables -A FORWARD -o wg0 -p tcp --dport 80   -d 10.0.1.6  -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -o wg0 -p tcp --dport 443  -d 10.0.1.6  -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -o wg0 -p tcp --dport 25565 -d 10.0.1.13 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -o wg0 -p udp --dport 19132 -d 10.0.1.13 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -o wg0 -p udp --dport 3478  -d 10.0.1.15 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i wg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

What these do:

- Allow new connections **only** to the specified services to be forwarded out of the tunnel.
- Allow return traffic for established connections back from the tunnel.
- Provide a minimal explicit forward policy so only intended ports are forwarded.

## serverone details

### WireGuard container

The WG container runs with:

- `NET_ADMIN` capability.
- `/dev/net/tun` device.
- `wg-quick up /config/wg0.conf` and stays alive.

The peer endpoint is `87.106.25.93:51820` (vps-proxy). The peer allows `0.0.0.0/0` so all replies can route back through the tunnel when policy routing selects it.

### Policy routing + connmark

Because WireGuard runs in a container, the host must explicitly route reply traffic back to the WG container gateway (`10.0.1.17`) rather than exiting via the default WAN. This is done with connmarking and policy routing.

#### Mangle rules (connmark)

```
iptables -t mangle -A PREROUTING -i nerdctl0 -s ! 10.0.1.0/24 -d 10.0.1.0/24 \
  -m conntrack --ctstate NEW -j CONNMARK --set-mark 0x1

iptables -t mangle -A PREROUTING -i nerdctl0 -m connmark --mark 0x1 -j CONNMARK --restore-mark
```

What these do:

- When a container receives a NEW connection from a non-container source, the connection is marked.
- The mark is restored on subsequent packets, so replies inherit the same mark.

This ensures reply traffic from the container is tied to the original inbound connection and can be policy-routed back through the WG container.

#### NAT bypass

```
iptables -t nat -I POSTROUTING -m connmark --mark 0x1 -j RETURN
```

What this does:

- Skips any later MASQUERADE rules (from CNI or other services) for marked connections.
- This prevents SNAT from overwriting the client IP on the way out.

#### Forwarding

```
iptables -A FORWARD -i nerdctl0 -o nerdctl0 -m connmark --mark 0x1 -j ACCEPT
```

What this does:

- Allows bridged forwarding for marked connections through the host.

#### Policy routing

```
ip rule add pref 100 fwmark 0x1 table 100
ip route replace default via 10.0.1.17 dev nerdctl0 table 100
```

What these do:

- Any packet marked `0x1` is routed using table `100`.
- Table `100` sends the packet to the WG container gateway, so replies go back through the tunnel.

This is the key piece that ensures responses to public traffic return through the same path and do not get sent out the host’s normal WAN, which would break the connection.

### Kernel and bridge settings

`br_netfilter` is enabled and `net.bridge.bridge-nf-call-iptables=1` ensures iptables sees bridged traffic between containers and the host.

## Why proxy protocol is no longer needed

Proxy protocol is used when a TCP proxy hides the client IP (e.g., FRP). In this design, the public edge only DNATs traffic and does not SNAT it. That means containers receive the original source IP directly, so nginx and other apps can use `$remote_addr` without any extra protocol.

## Operational checks

On vps-proxy:

```
wg show
iptables -t nat -S | sed -n '1,120p'
iptables -S FORWARD
```

On serverone:

```
wg show
ip rule show
ip route show table 100
iptables -t mangle -S
iptables -t nat -S POSTROUTING
```

If nginx is receiving real client IPs, `$remote_addr` should show the public client address in access logs.
