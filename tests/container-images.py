"""Check the module-generated OCI images and shared container identities."""

import json
import sys
import tarfile
import unittest
from pathlib import Path

CASES = json.loads(Path(sys.argv.pop(1)).read_text())


class ContainerImages(unittest.TestCase):
    def test_generated_metadata_and_defaults(self):
        identities = {case["name"]: case for case in CASES["identities"]}
        for case in CASES["images"]:
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
                    self.assertEqual(
                        config["Entrypoint"],
                        [CASES["tini"], "--"] + case["entrypoint"],
                    )
                    self.assertFalse(config.get("Env"))
                    self.assertFalse(config.get("Cmd"))
                    layer = manifest["layers"][0]
                    closure = layer["annotations"]["containerd.io/snapshot/nix-closure"]
                    store_paths = (
                        (Path(closure) / "store-paths").read_text().splitlines()
                    )
                    for arg in config["Entrypoint"]:
                        if arg.startswith("/nix/store/"):
                            store_path = "/".join(arg.split("/")[:4])
                            self.assertIn(store_path, store_paths)

                    layer_path = "blobs/" + layer["digest"].replace(":", "/")
                    with tarfile.open(fileobj=archive.extractfile(layer_path)) as root:
                        for path in [
                            "bin/sh",
                            "bin/env",
                            "bin/id",
                            "bin/sleep",
                            "bin/tini",
                            "etc/ssl/certs/ca-certificates.crt",
                            "etc/passwd",
                            "etc/group",
                            "etc/nsswitch.conf",
                        ]:
                            # buildEnv can link a whole directory (e.g. etc/ssl)
                            # rather than emitting a separate link for each file.
                            parts = Path(path).parts
                            for count in range(1, len(parts) + 1):
                                member = root.getmember("/".join(parts[:count]))
                                if member.issym():
                                    target = Path(member.linkname).joinpath(
                                        *parts[count:]
                                    )
                                    break
                            else:
                                self.fail(f"No store link for {path}")
                            self.assertTrue(target.is_absolute(), path)
                            self.assertTrue(target.exists(), path)
                            if path.startswith("etc/") and "/ssl/" not in path:
                                expected = Path(identities[case["name"]]["root"]) / path
                                self.assertEqual(
                                    target.read_text(), expected.read_text()
                                )

    def test_explicit_runtime_overrides_defaults(self):
        root = Path(CASES["overlap"]["root"])
        self.assertEqual(
            (root / "bin/sh").resolve(), Path(CASES["overlap"]["shell"]).resolve()
        )
        self.assertTrue((root / "bin/id").exists())
        self.assertTrue((root / "bin/tini").exists())
        self.assertTrue((root / "etc/nsswitch.conf").exists())

    def test_identities(self):
        for case in CASES["identities"]:
            with self.subTest(container=case["name"]):
                root = Path(case["root"])
                passwd = [
                    line.split(":")
                    for line in (root / "etc/passwd").read_text().splitlines()
                ]
                self.assertEqual(len(passwd), 3)
                users = {entry[0]: entry for entry in passwd}
                self.assertEqual(users["root"][2:4], ["0", "0"])
                self.assertEqual(users["nobody"][2:4], ["65534", "65534"])
                user = users[case["user"]]
                self.assertEqual(user[2:4], [str(case["uid"]), "5000"])
                self.assertEqual(user[5:], [case["home"], case["shell"]])
                group_lines = [
                    line.split(":")
                    for line in (root / "etc/group").read_text().splitlines()
                ]
                groups = {entry[0]: entry for entry in group_lines}
                self.assertEqual(groups["containers"][2:], ["5000", case["user"]])
                self.assertEqual(groups["root"][2], "0")
                self.assertEqual(groups["nogroup"][2], "65534")
                nss = (root / "etc/nsswitch.conf").read_text()
                self.assertIn("passwd: files\n", nss)
                self.assertIn("group: files\n", nss)
                self.assertIn("hosts: files dns\n", nss)


if __name__ == "__main__":
    unittest.main()
