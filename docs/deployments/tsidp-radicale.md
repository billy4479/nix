# Radicale calendar setup

With the tailnet connected, open `https://radicale.polpetta.online/setup/`. Sign in through tsidp and copy the server URL, username, and generated password into your app's CalDAV account settings. The same fields work for configuring another device. Use the full `https://` URL and enable SSL if the client asks. Calendar sync also requires the tailnet to be connected. The setup page prepares a private default calendar so the app has something to discover.

The page shows the same password each time. **Reset password** immediately replaces it for all devices; update each device's settings afterward. Your server URL, username and calendar data stay the same. The CalDAV username is `calendar-<Headscale user ID>`; changing a display name or email does not change it. Radicale serves CalDAV directly; it does not depend on tsidp for background sync.

## Before deploying

Register a confidential client named `radicale` in the tsidp admin UI. Set its redirect URI to `https://radicale.polpetta.online/setup/callback` and put the resulting client ID and secret in sops. If users still open the setup page on the legacy `.internal` hostname, keep `https://radicale.internal.polpetta.online/setup/callback` registered too. Provision all four keys before switching `serverone`:

| Key | Value |
| --- | --- |
| `radicale/oauth-client-id` | tsidp client ID |
| `radicale/oauth-client-secret` | tsidp client secret |
| `radicale/session-secret` | independent random secret, e.g. `openssl rand -hex 32` |
| `radicale/credential-key` | Fernet key: `python3 -c 'import secrets; print(secrets.token_urlsafe(32) + "=")'` |

Keep the credential key stable and back it up alongside the encrypted secrets. Back up `/mnt/SSD/apps/radicale`: it holds both the calendar collections and the `htpasswd` file with password hashes and encrypted copies. Do not edit that file manually. Losing the credential key makes existing passwords unrecoverable from the setup page.

After deployment, open the setup page over the tailnet, add a test CalDAV account, and check that it can create and sync an event. Test reset on that account before sharing the service. The existing `calendar-proxy` feeds are unchanged.
