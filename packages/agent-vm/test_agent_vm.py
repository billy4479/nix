import socket
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

from agent_vm import connect, load_profile, rpc
from broker import LEASE_SECONDS, QUEUE_SECONDS, Broker, Rejected, Server


class FakeVM:
    generation = None
    fail_clean = False

    def __init__(self):
        self.events = []
        self.generations = 0

    def clean(self, force=False):
        if self.fail_clean:
            raise OSError("disk is busy")
        self.events.append("clean")
        self.generation = None

    def start(self):
        self.events.append("start")
        if self.generation is None:
            self.generations += 1
            self.generation = str(self.generations)

    def stop(self):
        self.events.append("stop")

    def connect(self, timeout):
        local, self.guest = socket.socketpair()
        return local


class BrokerTests(unittest.TestCase):
    def setUp(self):
        self.now = 0
        self.vm = FakeVM()
        self.broker = Broker(self.vm, lambda: self.now)

    def action(self, action, profile, **fields):
        return self.broker.command((1000, profile), {"op": action, **fields})

    def test_shared_batch_then_exclusive_then_shared(self):
        self.assertEqual(self.action("request", "a", mode="shared")["state"], "active")
        self.assertEqual(self.action("request", "b", mode="shared")["state"], "active")
        self.assertEqual(self.action("request", "c", mode="exclusive")["position"], 1)
        self.assertEqual(self.action("request", "d", mode="shared")["position"], 2)
        self.action("release", "a")
        self.assertEqual(self.vm.events, ["clean", "start"])
        self.action("release", "b")
        self.assertEqual(self.action("status", "c")["state"], "active")
        self.assertEqual(self.action("status", "d")["state"], "queued")
        self.action("release", "c")
        self.assertEqual(self.action("status", "d")["state"], "active")
        self.assertEqual(self.vm.events, ["clean", "start"] * 3)

    def test_renewals_allowed_with_waiter_and_expiry_resets(self):
        self.action("request", "a", mode="shared")
        self.action("request", "b", mode="exclusive")
        self.now = LEASE_SECONDS - 1
        self.action("renew", "a")
        self.now = LEASE_SECONDS
        self.assertEqual(self.action("status", "b")["state"], "queued")
        self.now = 2 * LEASE_SECONDS - 1
        self.assertEqual(self.action("status", "b")["state"], "active")
        self.assertEqual(self.vm.events, ["clean", "start", "clean", "start"])

    def test_cancelling_exclusive_unblocks_later_shared(self):
        self.action("request", "a", mode="shared")
        self.action("request", "b", mode="exclusive")
        self.action("request", "c", mode="shared")
        self.action("cancel", "b")
        self.assertEqual(self.action("status", "c")["state"], "active")
        self.assertEqual(self.vm.events, ["clean", "start"])

    def test_expired_queue_entry_is_not_granted(self):
        self.action("request", "a", mode="exclusive")
        self.action("request", "b", mode="shared")
        self.now = QUEUE_SECONDS
        self.assertEqual(self.action("status", "b")["state"], "none")
        self.assertEqual(self.vm.events, ["clean", "start", "clean"])

    def test_power_preserves_disk_and_reset_retains_lease(self):
        self.action("request", "a", mode="exclusive")
        generation = self.vm.generation
        self.assertEqual(self.action("off", "a")["power"], "off")
        self.assertEqual(self.action("on", "a")["power"], "on")
        self.assertEqual(self.vm.generation, generation)
        self.assertEqual(self.action("reset", "a")["state"], "active")
        self.assertNotEqual(self.vm.generation, generation)
        self.action("release", "a")
        self.action("request", "b", mode="shared")
        for action in ("off", "on", "reset"):
            with self.assertRaisesRegex(Rejected, "exclusive"):
                self.action(action, "b")

    def test_cleanup_failure_fails_closed(self):
        self.action("request", "a", mode="exclusive")
        self.action("request", "b", mode="shared")
        self.vm.fail_clean = True
        with self.assertLogs(level="ERROR"), self.assertRaises(Rejected):
            self.action("release", "a")
        self.assertTrue(self.action("status", "b")["fault"])
        self.assertEqual(self.action("status", "b")["state"], "queued")
        self.assertEqual(self.vm.events, ["clean", "start"])

    def test_wire_proxy_is_revoked_at_shared_expiry(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener,
        ):
            path = str(Path(directory) / "sock")
            listener.bind(path)
            listener.listen()
            server = Server(listener, self.broker)
            worker = threading.Thread(
                target=server.serve_forever, kwargs={"poll_interval": 0.01}
            )
            worker.start()
            a, b = "a" * 64, "b" * 64
            try:
                rpc(path, a, "request", mode="shared")
                self.now = 1
                rpc(path, b, "request", mode="shared")
                with self.assertRaises(Rejected):
                    connect(path, a, "proxy", generation="stale")
                tunnel, _ = connect(path, a, "proxy", generation=self.vm.generation)
                with tunnel, self.vm.guest as guest:
                    tunnel.settimeout(2)
                    guest.settimeout(2)
                    tunnel.sendall(b"first bytes\n")
                    self.assertEqual(guest.recv(64), b"first bytes\n")
                    guest.sendall(b"reply")
                    self.assertEqual(tunnel.recv(64), b"reply")
                    self.now = LEASE_SECONDS
                    self.assertEqual(rpc(path, a, "status")["state"], "none")
                    self.assertEqual(tunnel.recv(64), b"")
                    self.assertEqual(rpc(path, b, "status")["state"], "active")
                    self.assertEqual(self.vm.events, ["clean", "start"])
            finally:
                server.shutdown()
                worker.join()

    def test_android_waiter_drains_nixos_and_clean_precedes_next_start(self):
        events = []

        class Backend(FakeVM):
            def __init__(self, name):
                super().__init__()
                self.name = name

            def clean(self, force=False):
                super().clean(force)
                events.append((self.name, "clean"))

            def start(self):
                super().start()
                events.append((self.name, "start"))

        self.broker = Broker(Backend("nixos"), lambda: self.now, Backend("android"))
        self.action("request", "linux", mode="shared")
        android = {"target": "android"}
        with self.assertRaisesRegex(Rejected, "exclusive"):
            self.action("request", "droid", mode="shared", **android)
        self.assertEqual(
            self.action("request", "droid", mode="exclusive", **android)["position"], 1
        )
        self.assertEqual(self.action("request", "later", mode="shared")["position"], 2)
        self.action("release", "linux")
        with self.assertRaisesRegex(Rejected, "already has"):
            self.action("release", "droid")
        with self.assertRaisesRegex(Rejected, "manual power"):
            self.action("off", "droid", **android)
        self.now = LEASE_SECONDS
        self.assertEqual(self.action("status", "later")["state"], "active")
        self.assertEqual(
            events,
            [
                ("nixos", "clean"),
                ("android", "clean"),
                ("nixos", "start"),
                ("nixos", "clean"),
                ("android", "start"),
                ("android", "clean"),
                ("nixos", "start"),
            ],
        )

    def test_android_reset_revokes_adb_proxy_and_watch(self):
        android = FakeVM()
        self.broker = Broker(self.vm, lambda: self.now, android)
        owner = (1000, "droid")
        self.action("request", "droid", mode="exclusive", target="android")
        old_generation = android.generation
        for action in ("adb-watch", "adb-proxy"):
            client, peer = socket.socketpair()
            with client, peer:
                generation = android.generation
                with self.assertRaises(Rejected):
                    self.broker.open_tunnel(owner, generation, client, "proxy")
                request, pair = self.broker.open_tunnel(
                    owner, generation, client, action
                )
                self.assertEqual(
                    self.action("reset", "droid", target="android")["state"], "active"
                )
                self.assertNotEqual(android.generation, old_generation)
                peer.settimeout(1)
                self.assertEqual(peer.recv(1), b"")
                with self.assertRaises(Rejected):
                    self.broker.open_tunnel(owner, generation, client, action)
                self.broker.close_tunnel(request, pair)
                if action == "adb-proxy":
                    android.guest.close()

    def test_profile_token_persists_and_is_private(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.dict("os.environ", XDG_STATE_HOME=directory),
        ):
            profile, token = load_profile("saved")
            self.assertEqual(load_profile("saved")[1], token)
            self.assertNotEqual(load_profile("fork")[1], token)
            self.assertEqual((profile / "token").stat().st_mode & 0o777, 0o600)
            with self.assertRaises(Rejected):
                load_profile("../unsafe")
