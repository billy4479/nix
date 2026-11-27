"""Check edge trust, restricted ACL ordering, and advertised QUIC coverage."""

import re
import sys
from pathlib import Path

config_dir = Path(sys.argv[1])
domain = sys.argv[2]
infrastructure = (config_dir / "nginx.conf").read_text()
vhosts = (config_dir / "vhosts.conf").read_text()
edges = ("10.100.0.1", "10.0.1.131")
# Explicit policy, not a deduction from DNS spelling.
admin_labels = {
    "agent-up",
    "grafana",
    "headplane",
    "jackett",
    "mircrewrr",
    "qbittorrent",
    "radarr",
    "sonarr",
    "syncthing",
    "t3code",
}
public_labels = {
    "calendar-proxy",
    "giuoco-del-divertimento",
    "headscale",
    "laurea",
    "lunamultiplayer",
    "mc-runner",
    "opencloud",
    "quote-bot",
}
seen_admin_names = set()
assert "map $server_name $backend {" in vhosts

for edge in edges:
    assert f"set_real_ip_from {edge};" in infrastructure, edge

# These server blocks contain nested locations but no nested server blocks.
# Slice at each server opening rather than attempting to parse nested braces.
for server in re.split(r"\bserver\s*\{", infrastructure)[1:]:
    if "listen 443 ssl" in server:
        assert "listen 443 quic" in server
servers = re.split(r"\bserver\s*\{", vhosts)[1:]
for server in servers:
    if re.search(
        rf"server_name\s+\*\.preview\.(?:internal\.)?{re.escape(domain)};", server
    ):
        assert re.findall(r"\blisten\s+([^;]+);", server) == ["8443 ssl"]
        assert re.findall(r"\ballow\s+([^;]+);", server) == ["100.64.0.0/10"]
        assert "deny all;" in server
        for edge in edges:
            assert server.index(f"deny {edge};") < server.index("allow ")
        continue
    name = re.search(r"server_name\s+([^;]+);", server)
    if not name:
        continue
    host = name.group(1)
    label = host.split(".")[0]
    listeners = re.findall(r"\blisten\s+([^;]+);", server)
    if label in admin_labels:
        if host == f"{label}.{domain}":
            seen_admin_names.add(label)
        assert listeners == ["8443 ssl"], host
        assert re.findall(r"\ballow\s+([^;]+);", server) == ["100.64.0.0/10"], host
    else:
        assert listeners == ["443 ssl", "443 quic", "4443 ssl proxy_protocol"], host
    if label not in public_labels:
        allow = server.index("allow ")
        for edge in edges:
            assert server.index(f"deny {edge};") < allow, (host, edge)
        assert "deny all;" in server, host
    else:
        assert "deny all;" not in server, host

assert seen_admin_names == admin_labels
