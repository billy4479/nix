# Switch qBittorrent between the VPS and home internet

On `serverone`, after deploying the configuration:

```sh
sudo torrent-egress status # Show the active policy
sudo torrent-egress home   # Use the home internet connection (enp2s0)
sudo torrent-egress vps    # Use vps-proxy through WireGuard (default)
```

Switching briefly restarts qBittorrent so peers and trackers reconnect through
the new path. Home mode exposes your home public IP to peers and lasts until
you switch back or reboot. It does not add an incoming port forward on your
home router. The VPS peer port is blocked while home mode is active.

In VPS mode, `vps-proxy` translates outbound IPv4 traffic (including tracker DNS)
to `87.106.25.93` and forwards inbound `6881/tcp` and `6881/udp` to the container.
If the tunnel is down, torrent traffic is blocked rather than falling back to
home. The tailnet Web UI, Sonarr/Radarr, and other services keep their existing
paths in both modes. IPv6 remains disabled in qBittorrent.

Deploy `serverone` first, then `vps-proxy`. qBittorrent's internet access may
pause between deployments. No home-router port forwarding is needed. Disable
UPnP/NAT-PMP in qBittorrent and clear any manually configured IP to report to
trackers or old interface binding. The app should listen on container port 6881,
not bind to `wg0` (that interface is on the host).

After deployment, check both modes with a torrent IP-check magnet, then leave
`vps` selected for the following checks:

- Use a torrent IP-check magnet to verify that peers see `87.106.25.93`.
- From outside the tailnet, verify that TCP port 6881 on `87.106.25.93` connects
  while qBittorrent is running. Confirm tracker/DHT traffic works for UDP.
- If you can briefly interrupt other public edge services, stop
  `wireguard-wg0.service` on `serverone`. The Web UI should still work locally
  via the tailnet, but qBittorrent should stop reaching internet peers and
  trackers, not fall back to the home connection. Start WireGuard again and
  confirm transfers resume.
