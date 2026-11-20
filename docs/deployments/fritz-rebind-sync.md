# FRITZ!Box DNS rebind exception sync

Keep `192.168.2.1` as the DHCP-advertised resolver. This job only changes the DNS rebind exception list on the FRITZ!Box. It does not change DHCP, upstream DNS, or public fallback.

On `serverone`, `fritz-rebind-sync.service` runs after the network comes online at boot and is queued on each NixOS activation. It reads `/etc/fritz-rebind-sync/manifest.json`, generated from web service domains, named raw service records, and the apex, `www`, and `internal` DNS entries. It adds missing names before pruning stale names **inside the deployment domain**. Names outside that domain are untouched. Add manually managed names in the deployment domain to `networking.fritzRebindSync.extraNames` before deploying if you need to keep them.

## Enable and check

The service skips until `/var/lib/fritz-rebind-sync/credential` exists. Provision that file on `serverone` as `root:root`, mode `0600`, with the FRITZ!Box admin username on line one and its password on line two. Use a local secret manager or `sudoedit`, not a Nix string or command-line argument. The file is passed using systemd credentials. Then switch configurations, or run `sudo systemctl start fritz-rebind-sync.service` after provisioning if the unit is already installed.

To preview without writing, build with `nix build .#fritz-rebind-sync` and run the executable on a machine with LAN access to the router:

```sh
sudo ./result/bin/fritz-rebind-sync --dry-run \
  /etc/fritz-rebind-sync/manifest.json /var/lib/fritz-rebind-sync/credential
```

Inspect `journalctl -u fritz-rebind-sync.service` for results. A router outage or an API change is reported as a unit failure; it does not change client DNS configuration. The HTTPS connection pins the router's public key, so confirm and update the pin in `system/hosts/serverone/fritz-rebind.nix` if that key changes.

## Router API

Verified on the FRITZ!Box 7530 with FRITZ!OS 8.25. The program uses AVM's version 2 PBKDF2 challenge at `/login_sid.lua?version=2` and sends the returned session as `Authorization: AVM-SID …`. The authenticated web UI API is not a stable public interface:

| Action | Request |
| --- | --- |
| List | `GET /api/v0/generic/dns_excepted_domains` |
| Add | `POST /api/v0/generic/dns_excepted_domains/domain` with JSON `{"name":"host.example.org"}` |
| Remove | `DELETE /api/v0/generic/dns_excepted_domains/domain/<UID>` using the ID from the list |

The router accepted exception changes without physical confirmation on this firmware. If newer firmware blocks headless changes, inspect the unit failure rather than disabling router confirmation.
