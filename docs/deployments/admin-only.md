# Admin-only dashboards on serverone

qBittorrent, Jackett and Syncthing keep their `https://<name>.internal.polpetta.online` URLs on TCP 443. Tailnet DNS sends those names to `10.0.2.6`, a dedicated subnet-routed address. Headscale authorizes `group:admin` (only `jack@`); serverone only forwards connections arriving on `tailscale0` for that address and port. The ordinary LAN and public listeners do not serve the dashboards. BitTorrent and Syncthing peer traffic is unchanged.

## Enable access

1. Back up the active Headscale policy in Headplane. Review [admin-only-policy.hujson](../../services/services/headscale/admin-only-policy.hujson) against that backup. It replaces the unrestricted `*:*` rule with explicit destinations, keeps the tsidp grant and includes access tests. Preserve any new rules that don't grant other users access to `10.0.2.6:443`. Check the candidate from the checkout, without applying it:

   ```sh
   ssh -T serverone 'sudo exec-in-container headscale headscale policy check -f /dev/stdin' \
     <services/services/headscale/admin-only-policy.hujson
   ```

2. Apply the checked policy in Headplane. **Do this before enabling admin ingress.** Do not restore a wildcard destination allow while admin ingress is enabled. Headscale grants are additive; group membership alone won't override a broader allow.
3. Set `polpetta.adminIngressEnabled = true;` in the serverone NixOS configuration and deploy. In Headplane, approve serverone's new `10.0.2.6/32` route **alongside** the existing `10.0.1.0/24` and exit routes. Jack's client must accept subnet routes and use tailnet DNS (Linux may need `tailscale set --accept-routes=true`). No VPS deployment is needed.
4. With passwords still in place, verify the three URLs work as Jack and fail from a non-admin tailnet node and from LAN with Tailscale off. Check direct attempts to `10.0.1.6:8443` and the app container ports also fail from those clients. Check other tailnet services, DNS, and exit-node use still work.

## Keep automation working

Radarr and Sonarr have bridge-only access to the qBittorrent and Jackett backends. Treat users with admin access to either Arr service as trusted. Persisted integration settings need to be updated once after deploying:

- qBittorrent: use host `10.0.1.5`, port `8080`, SSL off, and retain the existing credentials. If qBittorrent's Host header validation requires it, add `10.0.1.5` to its Web UI server domains alongside the dashboard hostname. Keep CSRF protection enabled.
- Jackett: use `http://10.0.1.8:9117` for the existing indexer URLs, keeping their paths and API keys.
- Run the built-in download-client and indexer tests in both Arr services. Syncthing device IDs, existing peer addresses and sync authentication don't change.

## Remove browser logins

After verifying the network restrictions, make these one-time changes in the apps' persisted UI settings:

- **qBittorrent:** Under Web UI, enable the authentication subnet bypass for `10.0.1.6/32` only. The allowlist must match nginx's socket address: leave qBittorrent's reverse proxy support off so it doesn't substitute the forwarded client IP for this check. Keep the Web UI credentials for Radarr and Sonarr.
- **Jackett:** Clear the admin password and save. Keep the API key.
- **Syncthing:** Under Settings → GUI, clear the GUI username and password and save. Keep the API key and device trust settings unchanged.

Test again in a fresh browser session as Jack. Before reverting to an older generation that serves these dashboards on LAN or on the ordinary tailnet listener, restore app authentication (remove the qBittorrent bypass and set Jackett and Syncthing passwords). To disable access without rolling back, set `polpetta.adminIngressEnabled = false` and redeploy.
