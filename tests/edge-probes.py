"""Public probes must use the VPS IP while preserving HTTP Host and TLS SNI."""

import json
import sys
from pathlib import Path
from urllib.parse import urlparse

import yaml

domain = sys.argv[3]
scrapes = json.loads(Path(sys.argv[1]).read_text())
modules = yaml.safe_load(Path(sys.argv[2]).read_text())["modules"]
edge_job = next(job for job in scrapes if job["job_name"] == "blackbox-edge")
edge_targets = {
    target["labels"]["service"]: target for target in edge_job["static_configs"]
}
assert "public-edge" in edge_targets

for name, target in edge_targets.items():
    assert len(target["targets"]) == 1, name
    url = urlparse(target["targets"][0])
    assert url.scheme == "https" and url.hostname == "87.106.25.93", (name, url)
    http = modules[target["labels"]["module"]]["http"]
    assert http["headers"]["Host"] == http["tls_config"]["server_name"], name
    host = http["headers"]["Host"]
    assert host == domain or host.endswith("." + domain), name
    assert not http["follow_redirects"], name

public_edge = edge_targets["public-edge"]
http = modules[public_edge["labels"]["module"]]["http"]
assert http["headers"]["Host"] == f"headscale.{domain}"
assert http["valid_status_codes"] == [200]
assert urlparse(public_edge["targets"][0]).path == "/health"
assert "public-headscale" not in edge_targets
for job in scrapes:
    if job["job_name"] == "blackbox-http":
        assert all(
            target["labels"].get("service") != "public-edge"
            for target in job["static_configs"]
        )
