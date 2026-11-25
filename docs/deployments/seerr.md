# Seerr media requests on serverone

Seerr uses the stable Nixpkgs package and stores its database and settings in
`/mnt/SSD/apps/seerr`. Back up that directory; it contains integration keys.
No VPS deployment is needed.

## First deployment: admin-only setup

1. Deploy serverone with `polpetta.seerrMemberAccess` still false. Seerr,
   Sonarr and Radarr now use the [admin-only tailnet route](admin-only.md).
   Open `https://sonarr.internal.polpetta.online` and
   `https://radarr.internal.polpetta.online` from an admin node. In each app,
   use the first-run prompt or **Settings → General → Security** to select
   **Forms** authentication and save an admin username and password. Verify
   both require login in a fresh browser session. Keep the existing API keys.
2. In Jellyfin's dashboard, enable **Quick Connect**. Open
   `https://seerr.internal.polpetta.online` and choose **Jellyfin**. Use
   `http://10.0.1.10:8096` as the internal server URL and
   `https://jellyfin.internal.polpetta.online` as the external URL. Initial
   Seerr setup requires a Jellyfin admin's native username and password;
   Quick Connect is only available after setup. If your admin is OIDC-only,
   use a Jellyfin admin account that has a native password.
3. In the Seerr wizard, select and sync the movie and TV libraries. Add and
   test both integrations with the existing keys from each Arr app's
   **Settings → General → Security**:

   | Service | Host | Port | SSL |
   | --- | --- | --- | --- |
   | Sonarr | `10.0.1.9` | `8989` | Off |
   | Radarr | `10.0.1.7` | `7878` | Off |

   Pick the existing root folders and quality profiles and mark each server
   as the default. These are private bridge addresses, not URLs to share.
   If either app has a URL base, also enter that base in Seerr.
4. In **Settings → Users**, enable new Jellyfin sign-ins. Grant **Request**
   and **Auto-Approve Movies / Series** if members should start downloads
   without approval. Leave admin and request-management permissions off.
   Defaults apply to new users; update already imported users individually.
   Test Quick Connect with a non-admin Jellyfin account from an admin device:
   sign in to Jellyfin via OIDC, choose **Quick Connect** in Seerr, and enter
   the displayed code under **Quick Connect** in Jellyfin.

## Second deployment: open the request portal

Set `polpetta.seerrMemberAccess = true;` in
`system/hosts/serverone/default.nix` and redeploy. Seerr keeps the same URL and
moves to the standard private web tier (tailnet and LAN), with Jellyfin login
still required. Re-resolve the hostname if your client cached the admin IP.
Sonarr and Radarr stay on the admin-only route. Verify from a non-admin tailnet
node that Seerr works, both Arr URLs and direct backend ports are blocked,
and an auto-approved request reaches the correct app.

Before resetting Seerr's data or restoring an uninitialized backup, disable
member access and redeploy so the setup wizard stays private.
