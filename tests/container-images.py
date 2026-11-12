"""Check the module-generated OCI images, not just the input declarations."""

import json
import sys
import tarfile
import unittest
from pathlib import Path

CASES = json.loads(Path(sys.argv.pop(1)).read_text())


class ContainerImages(unittest.TestCase):
    def test_generated_metadata(self):
        for case in CASES:
            with self.subTest(container=case["name"]):
                with tarfile.open(case["image"]) as archive:

                    def read_json(path):
                        return json.load(archive.extractfile(path))

                    def blob(digest):
                        return read_json("blobs/" + digest.replace(":", "/"))

                    index = read_json("index.json")
                    descriptor = index["manifests"][0]
                    self.assertEqual(
                        descriptor["annotations"]["org.opencontainers.image.ref.name"],
                        case["name"] + ":nix-local",
                    )
                    manifest = blob(descriptor["digest"])
                    config = blob(manifest["config"]["digest"])["config"]
                    self.assertEqual(config["Entrypoint"], case["entrypoint"])
                    self.assertFalse(config.get("Env"))
                    self.assertFalse(config.get("Cmd"))
                    closure = manifest["layers"][0]["annotations"][
                        "containerd.io/snapshot/nix-closure"
                    ]
                    store_paths = (
                        (Path(closure) / "store-paths").read_text().splitlines()
                    )
                    for arg in case["entrypoint"]:
                        if arg.startswith("/nix/store/"):
                            store_path = "/".join(arg.split("/")[:4])
                            self.assertIn(store_path, store_paths)


if __name__ == "__main__":
    unittest.main()
