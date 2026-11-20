# qBittorrent through vps-proxy

qBittorrent's off-bridge IPv4 traffic (including tracker DNS) uses the existing
WireGuard tunnel. `vps-proxy` translates outbound connections to `87.106.25.93`
and forwards inbound `6881/tcp` and `6881/udp` to the container. The home host
no longer publishes that port. The tailnet Web UI and same-bridge Sonarr/Radarr
connections still use their existing paths. IPv6 is disabled in this container.

Deploy `serverone` first, then `vps-proxy`. qBittorrent's internet access may
pause between deployments. No home-router port forwarding is needed. Disable
UPnP/NAT-PMP in qBittorrent and clear any manually configured IP to report to
trackers or old interface binding. The app should listen on container port 6881,
not bind to `wg0` (that interface is on the host).

After deployment:

- Use a torrent IP-check magnet to verify that peers see `87.106.25.93`.
- From outside the tailnet, verify that TCP port 6881 on `87.106.25.93` connects
  while qBittorrent is running. Confirm tracker/DHT traffic works for UDP.
- If you can briefly interrupt other public edge services, stop
  `wireguard-wg0.service` on `serverone`. The Web UI should still work locally
  via the tailnet, but qBittorrent should stop reaching internet peers and
  trackers, not fall back to the home connection. Start WireGuard again and
  confirm transfers resume.
