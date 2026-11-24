# Serverone service ingress cutover

First deploy the native nftables migration following [the networking notes](../SERVERONE_NETWORKING.md). The service ingress rollout is separate. It does not change the VPS configuration.

## Stage 1: move HTTP callers

Deploy with `polpetta.enforceContainerIngress = false` (the default). HTTP health probes now use nginx locally. Verify Grafana can query Prometheus and verify TCP 9090 is not reachable from the LAN, tailnet, VPS or another container. Grafana still uses the host bridge address on port 9090; Prometheus is not an nginx backend.

Check the persisted app settings, which Nix does not rewrite:

- In Radarr and Sonarr, point the qBittorrent client at `qbittorrent.internal.<domain>` on 443 with SSL enabled. Replace direct Jackett indexer URLs with `https://jackett.internal.<domain>/…`, retaining the existing paths, credentials and API keys. Run each client's built-in connection test and test an indexer search.
- In Jackett, set its FlareSolverr API URL to `https://byparr.internal.<domain>` and test an indexer that uses it. In Mircrewrr check for a persisted override of the same URL and test it. Check for other persisted indexers or integration URLs using `10.0.1.x` or the host's published ports.
- Verify a new Immich ML job and a Headplane API action. Their declared URLs now use nginx. Check that Immich's admin settings do not override the ML URL. The ML vhost only allows Immich's bridge IP.
- Verify OIDC login from the tailnet, qBittorrent's Web UI, and the nginx HTTPS probes. Keep the existing application settings handy for rollback.

## Stage 2: deny undeclared ingress

Set `polpetta.enforceContainerIngress = true` on serverone and deploy. Confirm that nginx still serves the apps, and that a LAN or tailnet client and an unrelated container cannot connect directly to web backends or other undeclared ports. Confirm DNS, Syncthing, database/cache clients, public gameplay and incoming BitTorrent. Check both public TCP and UDP forwards. Test with new connections: established sessions can survive a ruleset reload.

The generated policy covers service containers on the IPv4 bridge, including same-bridge traffic and traffic routed after host-port DNAT. Host-originated traffic is exempt. Standalone containers such as nginx stay outside this policy. If an application breaks after cutover, revert the flag and redeploy to restore the legacy ingress rules while investigating. That does not undo the Prometheus restriction or the native nftables migration.
