"""Check edge trust, restricted ACL ordering, and advertised QUIC coverage."""

import re
import sys
from pathlib import Path

config_dir = Path(sys.argv[1])
infrastructure = (config_dir / "nginx.conf").read_text()
vhosts = (config_dir / "vhosts.conf").read_text()
edges = ("10.100.0.1", "10.0.1.131")

for edge in edges:
    assert f"set_real_ip_from {edge};" in infrastructure, edge

# These server blocks contain nested locations but no nested server blocks.
# Slice at each server opening rather than attempting to parse nested braces.
servers = re.split(r"\bserver\s*\{", infrastructure + "\n" + vhosts)[1:]
for server in servers:
    name = re.search(r"server_name\s+([^;]+);", server)
    label = name.group(1) if name else "default server"
    if "listen 443 ssl" in server:
        assert "listen 443 quic" in server, f"Missing QUIC listener: {label}"
    if name and ".internal.polpetta.online" in label:
        allow = server.index("allow ")
        for edge in edges:
            assert server.index(f"deny {edge};") < allow, (label, edge)
