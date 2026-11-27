# agent-preview

A foreground lease broker and relay for applications inside a shared-UID agent container. The only dependencies are the Go standard library and Linux.

## Run under a supervisor

```sh
agent-preview serve --hostname preview.example.test --listen-address 10.0.1.27
```

The flags default to `AGENT_PREVIEW_HOSTNAME` and `AGENT_PREVIEW_LISTEN_ADDRESS`. The address must be a specific IPv4 address distinct from `127.0.0.1`. Run the broker as the same UID as the CLI. `SIGINT` and `SIGTERM` close all leases and exit; a restart begins without any leases. The control socket is `/tmp/agent-preview-$UID/broker.sock`. `AGENT_PREVIEW_SOCKET` can override it for both the broker and CLI; use a short absolute path in a private directory owned by that UID with mode `0700`.

The broker listens only on the configured address: HTTP on 19999, plus raw TCP and UDP ports as leased. The supervisor must publish the raw range on the same external port numbers and forward HTTPS to 19999. HTTPS ingress must preserve the lease hostname as `Host` (without a port) and set `X-Forwarded-Proto: https`. It must support HTTP/1.1 upgrades and disable proxy buffering for streaming. The broker routes only exact, active lease hostnames. It does not terminate TLS or authenticate incoming preview traffic.

## Manage a lease

Bind the application to `127.0.0.1` on a port from 20000 to 20063. Do not bind the application to `0.0.0.0`: a wildcard bind could occupy the relay port or expose the app directly.

```sh
agent-preview request --tcp 20000 --web
agent-preview request --tcp 20001
agent-preview request --udp 20002

# Set AGENT_PREVIEW_TOKEN to the token from the selected request response.
agent-preview status
agent-preview renew
agent-preview release
```

Commands return JSON. `request` includes the public `endpoint`, UTC `expires_at`, and a secret `token` used only to manage that lease. `status`, `renew`, and `release` accept `--token TOKEN` or `AGENT_PREVIEW_TOKEN` and do not echo the token. The token is not an access password for the endpoint; do not publish it. Same-UID processes are trusted rather than isolated from one another.

The default global limit is 16 active leases; `serve --max-leases N` can configure it. A conflict does not replace an existing lease: raw TCP and web share the TCP slot for an app port, while UDP has its own slot. A renewal resets expiration to 30 minutes from now and can be repeated indefinitely while the lease remains active. Release and expiration close live connections, including WebSockets, and discard UDP peer sockets. UDP tracks up to 128 peers per lease and drops idle peers after a minute without incoming datagrams. Each new web lease gets a fresh HTTPS hostname; raw endpoints are reused if the port is leased again.

## Verify locally

Run `go test ./...` or `go test -race ./...` in this directory. Tests bind local addresses only, using `127.0.0.2` as the relay address and `127.0.0.1` as the app address. The Nix package runs the tests in its check phase.
