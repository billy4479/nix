# Agent previews from T3 Code

`agent-preview` temporarily exposes an app running on T3 Code container loopback to devices in Headscale’s `group:admin`. The agent starts its own app and requests one protocol and port. The CLI returns JSON: share the endpoint, **not** the management token.

```sh
agent-preview request --tcp 20042 --web  # HTTPS and WebSockets
agent-preview request --tcp 20043        # native TCP
agent-preview request --udp 20044        # native UDP
```

Use `AGENT_PREVIEW_TOKEN` with `agent-preview status`, `renew`, and `release`. Leases last 30 minutes and can be renewed repeatedly. Release, expiry, and restart close access, not the app. Ports `20000–20063` are reserved; the default global limit is 16 active leases. A raw endpoint can be reused by another app later. Web leases get new, unguessable hostnames so old links never resolve to a later app. The hostname is not a credential; the admin ACL is the access control.

Web traffic travels over the tailnet to the admin address (`10.0.2.6:443`), through the dedicated nginx listener and to the preview relay. Native TCP and UDP use that same address and the requested port, and bypass nginx. nginx terminates HTTPS; a raw client and app negotiate their own application protocol. The relay can only connect back to T3 loopback. No public listener or VPS route is added.

Browser previews have separate origins but still share the site with other `polpetta.online` services. Only open previews you trust. Keep sensitive service session cookies host-only, and do not use preview subdomains as an isolation boundary for hostile code. Agents in T3 share a UID and network namespace, so lease tokens prevent accidental interference, not malicious interference between agents.

## Enable on serverone

1. Verify the existing [admin ingress](deployments/admin-only.md) works. Devices must use tailnet DNS and accept the admin subnet route. Preview is enabled in the serverone configuration, so do not deploy that configuration until its certificate exists.
2. As the operator, provision a separate Certbot lineage before enabling the nginx vhost. It uses DNS-01 with the existing Cloudflare credentials; no application DNS record needs to be public. Include both wildcard names so the hostname migration can be tested and rolled back without reissuing the certificate. Replace `polpetta.online` if using another flake domain.

   ```sh
   sudo exec-in-container certbot certbot certonly \
     --non-interactive --agree-tos --register-unsafely-without-email \
     --cert-name agent-preview.polpetta.online \
     --dns-cloudflare --dns-cloudflare-credentials /cloudflare.ini \
     --dns-cloudflare-propagation-seconds 60 \
     -d '*.preview.internal.polpetta.online' -d '*.preview.polpetta.online'
   ```

   The certbot deploy hook grants nginx's UID read access to the new web private key (Certbot otherwise creates it as `0600`, masking inherited ACLs). nginx's startup also repairs access for existing web lineages. The existing scheduled `certbot renew` and nginx reload handle subsequent renewals. Public certificate transparency may disclose the wildcard names, not the individual lease hostnames.
3. Deploy serverone after the certificate is in place. Verify `headscale policy check -f /etc/headscale/policy.hujson` inside the Headscale container. The range is granted separately for TCP and UDP, only at the admin address, never at the T3 bridge IP.
4. Request a web, TCP, and UDP lease from T3 and exercise each from an admin tailnet device. Then verify non-admin tailnet, LAN/off-tailnet, the ordinary nginx listeners, and direct access to the T3 bridge ports all fail. Check expiry with an open WebSocket or raw connection. Disable `polpetta.agentPreview.enable` and redeploy to close the preview ingress without disabling other admin services.

The `t3/migrate-service-hostnames` migration moves the generated private DNS records and new links from `preview.internal.polpetta.online` to `preview.polpetta.online` with the other service names. Preview leases are ephemeral: the server switch may revoke them, and agents should request a new link after cutover or rollback.
