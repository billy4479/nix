"""Check edge trust, restricted ACL ordering, and advertised QUIC coverage."""

import re
import sys
from pathlib import Path

config_dir = Path(sys.argv[1])
domain = sys.argv[2]
infrastructure = (config_dir / "nginx.conf").read_text()
vhosts = (config_dir / "vhosts.conf").read_text()
edges = ("10.100.0.1", "10.0.1.131")
admin_names = {
    f"{name}.internal.{domain}" for name in ("qbittorrent", "jackett", "syncthing")
}
seen_admin_names = set()
assert "map $server_name $backend {" in vhosts

for edge in edges:
    assert f"set_real_ip_from {edge};" in infrastructure, edge

# These server blocks contain nested locations but no nested server blocks.
# Slice at each server opening rather than attempting to parse nested braces.
servers = re.split(r"\bserver\s*\{", infrastructure + "\n" + vhosts)[1:]
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
    label = name.group(1) if name else "default server"
    if "listen 443 ssl" in server:
        assert "listen 443 quic" in server, f"Missing QUIC listener: {label}"
    if label in admin_names:
        seen_admin_names.add(label)
        assert re.findall(r"\blisten\s+([^;]+);", server) == ["8443 ssl"], label
        assert re.findall(r"\ballow\s+([^;]+);", server) == ["100.64.0.0/10"], label
        assert "deny all;" in server, label
    if name and f".internal.{domain}" in label:
        allow = server.index("allow ")
        for edge in edges:
            assert server.index(f"deny {edge};") < allow, (label, edge)

assert seen_admin_names == admin_names
