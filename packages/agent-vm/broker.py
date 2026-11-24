"""Lease scheduler and Unix-socket control/SSH transport."""

import hashlib
import json
import logging
import re
import socket
import socketserver
import struct
import threading
import time
from collections import deque
from dataclasses import dataclass, field

LEASE_SECONDS = 30 * 60
QUEUE_SECONDS = 2 * 60 * 60
MAX_REQUESTS = 64


class Rejected(Exception):
    pass


def disconnect(*sockets):
    for sock in sockets:
        try:
            sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass


@dataclass
class Request:
    owner: tuple
    mode: str
    deadline: float
    tunnels: list = field(default_factory=list)

    def public(self, now):
        uid, token = self.owner
        return {
            "id": hashlib.sha256(f"{uid}:{token}".encode()).hexdigest()[:16],
            "mode": self.mode,
            "seconds_left": max(0, int(self.deadline - now)),
        }

    def revoke_connections(self):
        for pair in self.tunnels:
            disconnect(*pair)


class Broker:
    def __init__(self, vm, now=time.monotonic):
        self.vm = vm
        self.now = now
        self.queue = deque()
        self.active = {}
        self.lock = threading.Lock()
        self.power = "off"
        self.fault = False
        self.vm.clean(force=True)

    def lifecycle(self, operation, *args):
        try:
            return operation(*args)
        except Exception as error:
            logging.exception("VM lifecycle operation failed; blocking new grants")
            self.fault = True
            self.power = "unknown"
            for request in self.active.values():
                request.revoke_connections()
            raise Rejected(
                "VM fault; an administrator must restart the broker and verify cleanup"
            ) from error

    def clean(self):
        self.lifecycle(self.vm.clean)
        self.power = "off"

    def start(self):
        self.lifecycle(self.vm.start)
        self.power = "on"

    def advance(self):
        now = self.now()
        self.queue = deque(r for r in self.queue if r.deadline > now)
        had_active = bool(self.active)
        for owner, request in list(self.active.items()):
            if request.deadline <= now:
                request.revoke_connections()
                del self.active[owner]
        if self.fault:
            return
        if had_active and not self.active:
            self.clean()
        while self.queue:
            request = self.queue[0]
            if self.active and (
                request.mode == "exclusive"
                or next(iter(self.active.values())).mode == "exclusive"
            ):
                break
            if not self.active:
                self.start()
            # Boot may outlive a stale queue entry. Don't grant an expired request.
            if request.deadline <= self.now():
                self.queue.popleft()
                if not self.active:
                    self.clean()
                continue
            self.queue.popleft()
            request.deadline = self.now() + LEASE_SECONDS
            self.active[request.owner] = request

    def status(self, owner, include_queue=False):
        now = self.now()
        result = {"state": "none", "power": self.power, "fault": self.fault}
        if owner in self.active:
            result.update(self.active[owner].public(now), state="active")
        for position, request in enumerate(self.queue, 1):
            if request.owner == owner:
                result.update(request.public(now), state="queued", position=position)
        if include_queue:
            result["holders"] = [r.public(now) for r in self.active.values()]
            result["queue"] = [r.public(now) for r in self.queue]
        return result

    def command(self, owner, message):
        with self.lock:
            self.advance()
            action = message["op"]
            request = self.active.get(owner)
            queued = next((r for r in self.queue if r.owner == owner), None)
            if action in ("status", "queue"):
                return self.status(owner, include_queue=action == "queue")
            if self.fault:
                raise Rejected(
                    "VM fault; an administrator must restart the broker and verify cleanup"
                )
            if action == "request":
                mode = message.get("mode")
                if mode not in ("shared", "exclusive"):
                    raise Rejected("mode must be shared or exclusive")
                existing = request or queued
                if existing and existing.mode != mode:
                    raise Rejected(
                        "release or cancel before requesting a different mode"
                    )
                if not existing:
                    if len(self.active) + len(self.queue) >= MAX_REQUESTS:
                        raise Rejected("too many VM requests")
                    self.queue.append(Request(owner, mode, self.now() + QUEUE_SECONDS))
                    self.advance()
            elif action == "cancel":
                if request:
                    raise Rejected("request already granted; use release")
                if queued:
                    self.queue.remove(queued)
                    self.advance()
            elif action == "release":
                if not request:
                    raise Rejected("no active lease; use cancel for a queued request")
                request.revoke_connections()
                del self.active[owner]
                if not self.active:
                    self.clean()
                self.advance()
            elif action == "renew":
                if not request:
                    raise Rejected("no active lease")
                request.deadline = self.now() + LEASE_SECONDS
            elif action == "ssh-config":
                if not request or self.power != "on":
                    raise Rejected("an active lease and a powered-on VM are required")
                return self.vm.credentials()
            elif action in ("on", "off", "reset"):
                if not request or request.mode != "exclusive":
                    raise Rejected("an exclusive lease is required")
                if action == "off" and self.power == "on":
                    request.revoke_connections()
                    self.lifecycle(self.vm.stop)
                    self.power = "off"
                if action == "reset":
                    request.revoke_connections()
                    self.clean()
                if action != "off" and self.power == "off":
                    self.start()
                self.advance()
            else:
                raise Rejected("unknown command")
            return self.status(owner)

    def open_tunnel(self, owner, generation, client):
        with self.lock:
            self.advance()
            request = self.active.get(owner)
            if (
                self.fault
                or not request
                or self.power != "on"
                or generation != self.vm.generation
            ):
                raise Rejected(
                    "SSH requires a current lease and fresh SSH configuration"
                )
            if (
                len(request.tunnels) >= 4
                or sum(len(r.tunnels) for r in self.active.values()) >= 32
            ):
                raise Rejected("too many SSH connections")
            try:
                guest = self.vm.connect(timeout=2)
            except OSError as error:
                raise Rejected("guest SSH is unavailable") from error
            guest.settimeout(None)
            pair = (client, guest)
            request.tunnels.append(pair)
            return request, pair

    def close_tunnel(self, request, pair):
        with self.lock:
            request.tunnels.remove(pair)
        pair[1].close()

    def tick(self):
        while True:
            time.sleep(1)
            with self.lock:
                try:
                    self.advance()
                except Rejected:
                    pass  # Lifecycle errors are already logged and latched.


def read_message(sock, limit=2048):
    # Don't buffer past the JSON header: the next bytes on a tunnel are SSH.
    end = time.monotonic() + 5
    data = bytearray()
    while len(data) < limit and time.monotonic() < end:
        sock.settimeout(max(0.001, end - time.monotonic()))
        byte = sock.recv(1)
        if not byte or byte == b"\n":
            break
        data.extend(byte)
    if byte != b"\n":
        raise Rejected("invalid message framing")
    try:
        value = json.loads(data)
    except (ValueError, RecursionError) as error:
        raise Rejected("invalid JSON message") from error
    if not isinstance(value, dict):
        raise Rejected("expected a JSON object")
    return value


def send_message(sock, **fields):
    sock.sendall(json.dumps(fields, separators=(",", ":")).encode() + b"\n")


def relay(source, destination):
    try:
        while data := source.recv(65536):
            destination.sendall(data)
        destination.shutdown(socket.SHUT_WR)
    except OSError:
        disconnect(source, destination)


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        client = self.request
        broker = self.server.broker
        try:
            message = read_message(client)
            token, action = message.get("token"), message.get("op")
            if (
                not isinstance(token, str)
                or re.fullmatch(r"[0-9a-f]{64}", token) is None
                or not isinstance(action, str)
            ):
                raise Rejected("invalid request")
            _, uid, _ = struct.unpack(
                "3i", client.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
            )
            owner = (uid, token)
            if action != "proxy":
                send_message(client, ok=True, result=broker.command(owner, message))
                return
            request, pair = broker.open_tunnel(owner, message.get("generation"), client)
            try:
                send_message(client, ok=True)
                client.settimeout(None)
                outgoing = threading.Thread(target=relay, args=pair, daemon=True)
                outgoing.start()
                relay(*reversed(pair))
                outgoing.join()
            finally:
                disconnect(*pair)
                broker.close_tunnel(request, pair)
        except Rejected as error:
            try:
                send_message(client, ok=False, error=str(error))
            except OSError:
                pass
        except OSError:
            pass  # Client disconnected or did not send a header in time.


class Server(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True

    def __init__(self, listener, broker):
        socketserver.BaseServer.__init__(self, "agent-vm", Handler)
        self.socket = listener
        self.broker = broker
        self.slots = threading.BoundedSemaphore(64)

    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()
