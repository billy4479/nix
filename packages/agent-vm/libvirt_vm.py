"""Libvirt lifecycle for exactly one transient VM."""

import os
import secrets
import socket
import subprocess
import tempfile
import time
from pathlib import Path
from xml.sax.saxutils import quoteattr

NAME = "agent-dev"
UUID = "eaf17a2d-13c2-4275-9c06-d7019af145b5"


def run(*args, timeout=30):
    result = subprocess.run(args, timeout=timeout, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def virsh(*args):
    return run("virsh", "--connect", "qemu:///system", *args)


class LibvirtVM:
    def __init__(self, storage, base, guest_ip, bridge):
        self.storage = Path(storage)
        if not self.storage.is_mount():
            raise RuntimeError("VM storage must be a dedicated mounted filesystem")
        self.base = base
        self.guest_ip = guest_ip
        self.bridge = bridge
        self.disk = self.storage / "guest.qcow2"
        self.seed = self.storage / "seed.iso"
        self.xml = self.storage / "domain.xml"
        self.generation = None
        self.credentials_data = None

    def running(self):
        return UUID in virsh("list", "--uuid").splitlines()

    def stop(self, force=False):
        if not self.running():
            return
        if not force:
            try:
                virsh("shutdown", UUID, "--mode", "acpi")
            except RuntimeError:
                if self.running():
                    raise
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                if not self.running():
                    return
                time.sleep(0.5)
        if self.running():
            virsh("destroy", UUID)
        if self.running():
            raise RuntimeError("VM did not stop")

    def clean(self, force=False):
        # Never discard a disk unless libvirt has confirmed the domain is gone.
        self.stop(force)
        for path in (self.xml, self.seed, self.disk):
            path.unlink(missing_ok=True)
        self.generation = None
        self.credentials_data = None

    def prepare(self):
        run("cp", "--reflink=auto", "--sparse=always", self.base, self.disk)
        self.disk.chmod(0o600)
        self.generation = secrets.token_hex(16)
        with tempfile.TemporaryDirectory(prefix="agent-vm-") as tmp:
            tmp = Path(tmp)
            seed_data = tmp / "seed"
            seed_data.mkdir()
            host = seed_data / "host_key"
            login = tmp / "login"
            for key in (host, login):
                run("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", key)
            (seed_data / "authorized_keys").write_text(
                login.with_suffix(".pub").read_text()
            )
            run(
                "xorriso",
                "-as",
                "mkisofs",
                "-quiet",
                "-R",
                "-V",
                "AGENTVM_SEED",
                "-o",
                self.seed,
                seed_data,
            )
            self.seed.chmod(0o600)
            self.credentials_data = {
                "generation": self.generation,
                "identity": login.read_text(),
                "host_key": " ".join(host.with_suffix(".pub").read_text().split()[:2]),
            }

        self.xml.write_text(f"""<domain type='kvm'>
  <name>{NAME}</name><uuid>{UUID}</uuid>
  <memory unit='MiB'>3072</memory><vcpu>2</vcpu>
  <os><type arch='x86_64' machine='q35'>hvm</type><boot dev='hd'/></os>
  <features><acpi/><apic/></features>
  <on_poweroff>destroy</on_poweroff><on_reboot>restart</on_reboot><on_crash>destroy</on_crash>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/><source file={quoteattr(str(self.disk))}/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/><source file={quoteattr(str(self.seed))}/>
      <target dev='sda' bus='sata'/><readonly/>
    </disk>
    <interface type='bridge'>
      <source bridge={quoteattr(self.bridge)}/><model type='virtio'/>
    </interface>
    <serial type='pty'/><console type='pty'/>
    <memballoon model='none'/>
  </devices>
</domain>
""")

    def start(self):
        if self.generation is None:
            self.prepare()
        if not self.running():
            virsh("create", str(self.xml))
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            try:
                with self.connect(timeout=1):
                    return
            except OSError:
                time.sleep(0.5)
        raise RuntimeError("guest did not start SSH")

    def connect(self, timeout):
        return socket.create_connection((self.guest_ip, 22), timeout=timeout)

    def credentials(self):
        return self.credentials_data


def activated_listener():
    if (
        os.environ.get("LISTEN_PID") != str(os.getpid())
        or os.environ.get("LISTEN_FDS") != "1"
    ):
        raise RuntimeError("broker requires one socket from systemd socket activation")
    listener = socket.socket(fileno=3)
    if listener.family != socket.AF_UNIX or not listener.getsockopt(
        socket.SOL_SOCKET, socket.SO_ACCEPTCONN
    ):
        raise RuntimeError("broker requires a listening Unix socket")
    return listener
