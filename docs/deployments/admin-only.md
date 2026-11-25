# Admin-only dashboards on serverone

qBittorrent, Jackett, Syncthing, Sonarr and Radarr keep their `https://<name>.internal.polpetta.online` URLs on TCP 443. Tailnet DNS sends those names to `10.0.2.6`, a dedicated subnet-routed address. Headscale authorizes `group:admin` (only `jack@`); serverone only forwards connections arriving on `tailscale0` for that address and port. The ordinary LAN and public listeners do not serve the dashboards. BitTorrent and Syncthing peer traffic is unchanged.

## Enable access

1. Back up the active database policy from Headplane before the first deploy. Compare it with [policy.nix](../../services/services/headscale/policy.nix) and merge any newer rules into Git. The generated JSON replaces the unrestricted `*:*` rule with explicit destinations and keeps the tsidp grant. Never add a broader allow that would include the admin IP. Headscale ACLs are additive.
2. Deploy serverone with `polpetta.adminIngressEnabled` still off. Headscale then loads the Nix-mounted file instead of its database policy. Future policy edits go through Git and a serverone deployment, not Headplane. The existing database still holds enrolled nodes and users.
3. Once Headscale is serving the new policy, apply the `tag:serverone` tag to serverone's existing node. Verify the node ID before tagging. This changes the node from user-owned to tag-owned; it will no longer inherit Jack's admin access. No other node should get the tag.

   ```sh
   sudo exec-in-container headscale headscale nodes list
   sudo exec-in-container headscale headscale nodes tag --identifier 10 --tags tag:serverone
   sudo exec-in-container headscale headscale policy check -f /etc/headscale/policy.hujson
   ```

4. Set `polpetta.adminIngressEnabled = true;` in the serverone NixOS configuration and deploy. The file policy automatically approves `10.0.2.6/32` for `tag:serverone`; the existing subnet and exit route approvals are unchanged. Check with `sudo exec-in-container headscale headscale nodes list-routes`. Jack's client must accept subnet routes and use tailnet DNS (Linux may need `tailscale set --accept-routes=true`). No VPS deployment is needed.
5. With passwords still in place, verify the dashboard URLs work as Jack and fail from a non-admin tailnet node and from LAN with Tailscale off. Check direct attempts to `10.0.1.6:8443` and the app container ports also fail from those clients. Check other tailnet services, DNS, and exit-node use still work.

## Keep automation working

Radarr and Sonarr have bridge-only access to the qBittorrent and Jackett backends. Treat users with admin access to either Arr service as trusted. Persisted integration settings need to be updated once after deploying:

- qBittorrent: use host `10.0.1.5`, port `8080`, SSL off, and retain the existing credentials. If qBittorrent's Host header validation requires it, add `10.0.1.5` to its Web UI server domains alongside the dashboard hostname. Keep CSRF protection enabled.
- Jackett: use `http://10.0.1.8:9117` for the existing indexer URLs, keeping their paths and API keys.
- Run the built-in download-client and indexer tests in both Arr services. Syncthing device IDs, existing peer addresses and sync authentication don't change.

## Remove browser logins

Keep browser authentication enabled for Sonarr and Radarr. See [Seerr deployment](seerr.md) for their password and request-portal setup.

After verifying the network restrictions, make these one-time changes in the apps' persisted UI settings:

- **qBittorrent:** Under Web UI, enable the authentication subnet bypass for `10.0.1.6/32` only. The allowlist must match nginx's socket address: leave qBittorrent's reverse proxy support off so it doesn't substitute the forwarded client IP for this check. Keep the Web UI credentials for Radarr and Sonarr.
- **Jackett:** Clear the admin password and save. Keep the API key.
- **Syncthing:** Under Settings → GUI, clear the GUI username and password and save. Keep the API key and device trust settings unchanged.

Test again in a fresh browser session as Jack. Before restoring the old database policy, disable admin ingress and redeploy. Before reverting to an older generation that serves these dashboards on LAN or on the ordinary tailnet listener, restore app authentication (remove the qBittorrent bypass and set Jackett and Syncthing passwords). To disable access without rolling back, set `polpetta.adminIngressEnabled = false` and redeploy.
