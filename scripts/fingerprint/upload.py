"""Offline upload experiment with simulated SPI, acknowledgements and replies.

The original driver builds packets and handles retries. The final SPB/WDF write
is intercepted and copied into Python memory, never submitted to an OS/device.
DPAPI, randomness, cache files, waits and locks are explicitly mocked.
"""

import struct

from machine import HEAP

TEST_KEY = bytes(range(32))
TEST_SEED = b"TESTSEED"
FAKE_SEALED = b"FAKE_DPAPI" + bytes(190)


def message(command: int, payload: bytes) -> bytes:
    """Independent Goodix command encoder, for expected bytes and mock replies."""
    header = bytes([command]) + struct.pack("<H", len(payload) + 1)
    return header + payload + bytes([(0xAA - sum(header + payload)) & 0xFF])


def parcels(command: int, payload: bytes, counter: int = 0) -> list[bytes]:
    inner = message(command, payload)
    header = b"\xa0" + struct.pack("<H", len(inner))
    record = header + bytes([sum(header) & 0xFF]) + inner
    record += bytes(-len(record) % 4)
    result = []
    for offset in range(0, len(record), 252):
        counter = (counter + 1) & 0xFFFF
        result.append(
            b"\xcc\xf2" + struct.pack("<H", counter) + record[offset : offset + 252]
        )
    return result


def provisioning(wrapper: bytes, sealed: bytes = FAKE_SEALED) -> bytes:
    data = struct.pack("<II", 0xBB010002, len(sealed) + 8)
    data += sealed + TEST_SEED
    data += struct.pack("<II", 0xBB010003, len(wrapper)) + wrapper
    return data + bytes(-len(data) % 4)


class Upload:
    def __init__(
        self, driver, *, ack_after=1, completion_after=1, status=0, fail_write=None
    ):
        self.machine = machine = driver.machine()
        self.ack_after = ack_after
        self.completion_after = completion_after
        self.status = status
        self.fail_write = fail_write
        self.writes = []
        self.commands = []
        self.waits = []
        self.sleeps = []
        self.events = []
        self.uploads = []
        self.caches = []
        self.reply_data = b""
        self.cache_result = None
        self.current = (14, 0)
        self.base = machine.base
        for rva in (0xCEA0, 0xD684, 0x13600, 0x7A20):  # logging only
            machine.hooks[rva] = lambda _: 0
        machine.hooks.update(
            {
                0xF8B8: self._sleep,
                0x12A50: self._write,
                0x5F0AC: self._command,
                0x41D68: self._upload,
                0x3F52C: self._entropy,
                0xB8D4: self._random,
                0xBC34: self._seal,
                0xB5C8: lambda _: HEAP + 0x9000,
                0x8758: self._cache,
            }
        )
        for name in ("EnterCriticalSection", "LeaveCriticalSection", "ResetEvent"):
            machine.apis[name] = lambda _: 1
        machine.apis.update(
            {
                "SetEvent": self._event,
                "WaitForSingleObject": self._wait,
                "Sleep": self._sleep,
            }
        )
        machine.write(self.base + 0xC5430, struct.pack("<I", 1))  # ITE transport
        machine.write(self.base + 0xD8E90, struct.pack("<Q", HEAP + 0x8000))
        machine.write(HEAP + 0x8000, struct.pack("<11Q", *range(1, 12)))
        machine.write(self.base + 0xD8EC8, struct.pack("<Q", 8))
        machine.write(self.base + 0xD8E88, struct.pack("<Q", HEAP + 0xA000))
        machine.write(HEAP + 0xA210, struct.pack("<Q", 99))

    def _command(self, machine):
        self.current = (machine.arg(1) & 0xFF, machine.arg(2) & 0xFF)
        self.commands.append(self.current)
        # Observe entry only; execute the original command builder.

    def _upload(self, machine):
        self.uploads.append(machine.read(machine.arg(0), machine.arg(1) & 0xFFFFFFFF))

    def _write(self, machine):
        self.writes.append(machine.read(machine.arg(2), machine.arg(3) & 0xFFFFFFFF))
        if self.fail_write == 0 or self.fail_write == len(self.writes):
            return 0xC0000001
        group, subcommand = self.current
        if self.ack_after is not None and len(self.writes) >= self.ack_after:
            machine.write(self.base + 0xECC20 + (group * 8 + subcommand) * 24, b"\1")
        body = bytes([self.status]) + self.reply_data
        machine.write(self.base + 0xD8F88, struct.pack("<I", len(body)) + body)
        return 0

    def _wait(self, machine):
        self.waits.append(machine.arg(1))
        if (
            self.completion_after is not None
            and len(self.commands) >= self.completion_after
        ):
            return 0
        return 0x102  # WAIT_TIMEOUT, with no real waiting

    def _sleep(self, machine):
        self.sleeps.append(machine.arg(0))
        return 0

    def _event(self, machine):
        self.events.append(machine.arg(0))
        return 1

    def _entropy(self, machine):
        machine.write(machine.arg(0), bytes(48))
        machine.write(machine.arg(1), struct.pack("<I", 48))
        machine.write(machine.arg(2), TEST_SEED)
        return 0

    def _random(self, machine):
        machine.write(machine.arg(0), TEST_KEY)
        return 0

    def _seal(self, machine):
        machine.write(machine.arg(4), FAKE_SEALED)
        machine.write(machine.arg(5), struct.pack("<I", len(FAKE_SEALED)))
        return 0

    def _cache(self, machine):
        data = machine.read(machine.arg(1), machine.arg(2))
        self.caches.append(data)
        return len(data) if self.cache_result is None else self.cache_result

    def write_key(self):
        """Execute production_write_key with synthetic random/DPAPI fixtures."""
        return self.machine.call(0x41460, HEAP)

    def send(self, payload):
        self.machine.write(HEAP, payload)
        return self.machine.call(0x41D68, HEAP, len(payload))

    def receive(self, command, payload):
        """Feed a synthetic inner reply to the original Goodix response parser."""
        frame = message(command, payload)
        self.machine.write(HEAP + 0x4000, frame)
        self.machine.call(0x606EC, HEAP + 0x4000, len(frame))
