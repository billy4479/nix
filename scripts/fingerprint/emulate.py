"""Hash-pinned Goodix driver image and offline key-wrapping experiment."""

import hashlib
import struct
from pathlib import Path

import pefile
from machine import HEAP, Machine

DRIVER_SHA256 = "074c7425704bc61cab63ab61ff9c50dcae6eb0dd896c87b0e2f0c862e585aa34"


class Driver:
    def __init__(self, path: Path):
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != DRIVER_SHA256:
            raise ValueError(
                "Unsupported gfspi.dll: addresses require version 1.1.17.140"
            )
        self.pe = pefile.PE(data=data)

    def machine(self) -> Machine:
        return Machine(self.pe)

    def wrap(self, psk: bytes, mode: int) -> tuple[bytes, bytes]:
        if len(psk) != 32 or mode not in (0, 1):
            raise ValueError("Expected a 32-byte synthetic key and mode 0 or 1")
        machine = self.machine()
        machine.write(machine.base + 0xEFEFC, struct.pack("<I", mode))
        machine.call(0x6640 if mode == 0 else 0x5F30, HEAP)
        machine.call(0x6950 if mode == 0 else 0x62C0, HEAP + 16)
        seed = machine.read(HEAP, 32)
        machine.write(HEAP + 0x100, psk)
        machine.write(HEAP + 0x200, struct.pack("<I", 0x800))
        result = machine.call(0x6C60, HEAP + 0x100, 32, HEAP + 0x1000, HEAP + 0x200)
        length = machine.uint(HEAP + 0x200)
        if result != 0 or length != 102:
            raise RuntimeError(f"Wrapping failed: status={result:#x}, length={length}")
        return seed, machine.read(HEAP + 0x1000, length)
