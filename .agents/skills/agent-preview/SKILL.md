---
name: agent-preview
description: Request, renew, or release a temporary admin-only forward to an app running inside the T3 Code container.
---

Start the app on `127.0.0.1` using an unused port in `20000–20063`. Do not bind it to all interfaces. Request only the transport needed:

```sh
agent-preview request --tcp 20042 --web  # HTTPS, including WebSockets
agent-preview request --tcp 20043        # native TCP
agent-preview request --udp 20044        # native UDP
```

Share only the returned endpoint (and protocol for raw forwards), not the management token. The reviewer must be on the admin tailnet. If there is a port conflict, choose a different app port; never stop another agent's process.

Save the returned token privately for this lease. Use `agent-preview status`, `agent-preview renew`, and `agent-preview release` with `AGENT_PREVIEW_TOKEN` set to that token. Leases expire after 30 minutes; renew only when the preview is still needed. Releasing or expiring a forward closes access but does not stop the app, so clean up the app separately.

For a dev server that validates hostnames, allow the exact returned HTTPS hostname rather than disabling its Host checks. A web preview does not grant raw access to its TCP port. Raw endpoints can be reused after release, so don't treat them as permanent links.
