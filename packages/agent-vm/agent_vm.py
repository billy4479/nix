"""Standalone client and broker entry point."""

import argparse
import fcntl
import json
import logging
import os
import re
import secrets
import shlex
import shutil
import socket
import sys
import tempfile
import threading
import time
from pathlib import Path

from broker import Broker, Rejected, Server, read_message, send_message
from libvirt_vm import LibvirtVM, activated_listener

SOCKET = "/run/agent-vm/control.sock"


def atomic_write(path, contents):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as f:
        temporary = Path(f.name)
        try:
            f.write(contents)
            f.flush()
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def load_profile(name):
    if not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", name):
        raise Rejected(
            "profile must be 1 to 64 letters, digits, underscores or hyphens"
        )
    state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    directory = (state / "agent-vm" / name).absolute()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (directory / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = directory / "token"
        if not path.exists():
            atomic_write(path, secrets.token_hex(32))
        return directory, path.read_text().strip()


def connect(path, token, action, **fields):
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.settimeout(5)
        sock.connect(path)
        send_message(sock, op=action, token=token, **fields)
        # An initial request may synchronously have to create and boot a guest.
        sock.settimeout(180)
        if not sock.recv(1, socket.MSG_PEEK):
            raise Rejected("broker closed the connection")
        response = read_message(sock, limit=16384)
        if not response.get("ok"):
            raise Rejected(response.get("error", "broker rejected request"))
        return sock, response.get("result")
    except BaseException:
        sock.close()
        raise


def rpc(path, token, action, **fields):
    sock, result = connect(path, token, action, **fields)
    sock.close()
    return result


def proxy(path, token, generation):
    sock, _ = connect(path, token, "proxy", generation=generation)
    with sock:
        sock.settimeout(None)

        def upload():
            try:
                while data := os.read(0, 65536):
                    sock.sendall(data)
                sock.shutdown(socket.SHUT_WR)
            except OSError:
                pass

        threading.Thread(target=upload, daemon=True).start()
        while data := sock.recv(65536):
            view = memoryview(data)
            while view:
                view = view[os.write(1, view) :]


def ssh_config(path, token, profile, directory):
    credentials = rpc(path, token, "ssh-config")
    generation = credentials["generation"]
    if not re.fullmatch(r"[0-9a-f]{32}", generation):
        raise Rejected("invalid VM generation")
    # Freeze the state path for ProxyCommand even when invoked from another shell.
    prefix = shlex.join(
        [
            "env",
            f"XDG_STATE_HOME={directory.parent.parent}",
            "agent-vm",
            "--socket",
            path,
            "--profile",
            profile,
            "proxy",
            generation,
        ]
    ).replace("%", "%%")

    def ssh_path(file):
        return (
            '"'
            + str(file).replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%")
            + '"'
        )

    identity = directory / "identity"
    known_hosts = directory / "known_hosts"
    conf = directory / "ssh.conf"
    if any(c in str(directory) + path for c in "\r\n"):
        raise Rejected("paths may not contain line breaks")
    with (directory / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        atomic_write(identity, credentials["identity"])
        atomic_write(known_hosts, f"agent-vm-{generation} {credentials['host_key']}\n")
        atomic_write(
            conf,
            f"""Host agent-vm
    HostName agent-vm
    HostKeyAlias agent-vm-{generation}
    User agent
    IdentityFile {ssh_path(identity)}
    UserKnownHostsFile {ssh_path(known_hosts)}
    GlobalKnownHostsFile /dev/null
    IdentitiesOnly yes
    IdentityAgent none
    StrictHostKeyChecking yes
    UpdateHostKeys no
    ForwardAgent no
    ControlMaster no
    BatchMode yes
    ProxyCommand {prefix}
""",
        )
    print(conf)


def serve(args):
    logging.basicConfig(level=logging.INFO)
    with activated_listener() as listener:
        vm = LibvirtVM(args.storage, args.base_image, args.guest_ip, args.bridge)
        broker = Broker(vm)
        threading.Thread(target=broker.tick, daemon=True).start()
        Server(listener, broker).serve_forever()


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(prog="agent-vm", description=__doc__)
    parser.add_argument(
        "--profile",
        default=os.environ.get("AGENT_VM_PROFILE"),
        help="explicit, unique client profile",
    )
    parser.add_argument("--socket", default=os.environ.get("AGENT_VM_SOCKET", SOCKET))
    commands = parser.add_subparsers(dest="action", required=True)
    request = commands.add_parser("request", help="request a shared or exclusive lease")
    request.add_argument("mode", choices=["shared", "exclusive"])
    wait = commands.add_parser("wait", help="wait for this profile's queued request")
    wait.add_argument(
        "--timeout", type=int, default=300, help="seconds to wait (default: 300)"
    )
    for name, help_text in {
        "status": "show this profile's request or lease",
        "queue": "show current holders and queued requests",
        "cancel": "cancel a queued request",
        "renew": "extend the current lease by setting its remaining time to 30 minutes",
        "release": "release a lease (last release discards VM state)",
        "on": "power on (exclusive)",
        "off": "power off without resetting the disk (exclusive)",
        "reset": "discard disk state and boot clean without releasing the lease (exclusive)",
        "ssh-config": "write and print the path to a lease-scoped OpenSSH configuration",
    }.items():
        commands.add_parser(name, help=help_text)
    commands.add_parser("proxy").add_argument("generation")
    for name, tip in (
        ("serve", "run the socket-activated broker"),
        ("cleanup", "discard the broker's VM (host admin)"),
    ):
        broker = commands.add_parser(name, help=tip)
        for arg in ("storage", "base-image", "guest-ip", "bridge"):
            broker.add_argument(f"--{arg}", required=True)
    args = parser.parse_args()
    if args.action == "serve":
        serve(args)
        return 0
    if args.action == "cleanup":
        LibvirtVM(args.storage, args.base_image, args.guest_ip, args.bridge).clean(
            force=True
        )
        return 0
    if not args.profile:
        parser.error("select a unique client using --profile or AGENT_VM_PROFILE")
    directory, token = load_profile(args.profile)
    path = os.path.abspath(args.socket)
    if args.action == "ssh-config":
        if not shutil.which("agent-vm"):
            raise Rejected("agent-vm must be on PATH for SSH ProxyCommand")
        ssh_config(path, token, args.profile, directory)
    elif args.action == "proxy":
        proxy(path, token, args.generation)
    elif args.action == "wait":
        if args.timeout < 0:
            parser.error("--timeout cannot be negative")
        deadline = time.monotonic() + args.timeout
        while True:
            result = rpc(path, token, "status")
            if (
                result["fault"]
                or result["state"] != "queued"
                or time.monotonic() >= deadline
            ):
                print(json.dumps(result))
                return 0 if result["state"] == "active" and not result["fault"] else 1
            time.sleep(min(1, max(0, deadline - time.monotonic())))
    else:
        fields = {"mode": args.mode} if args.action == "request" else {}
        print(json.dumps(rpc(path, token, args.action, **fields), indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (Rejected, OSError) as error:
        print(f"agent-vm: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
