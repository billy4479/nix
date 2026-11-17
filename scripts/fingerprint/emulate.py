"""Emulate only the pure key-wrapping routines of one known Goodix driver.

No Windows APIs, driver entry points, device I/O, or provisioning are executed.
Memory allocation, free, and stack-cookie checks are intercepted locally.
"""

import hashlib
import struct
from pathlib import Path

import pefile
from unicorn import UC_ARCH_X86, UC_HOOK_CODE, UC_MODE_64, Uc
from unicorn.x86_const import (
    UC_X86_REG_R8,
    UC_X86_REG_R9,
    UC_X86_REG_RAX,
    UC_X86_REG_RCX,
    UC_X86_REG_RDX,
    UC_X86_REG_RIP,
    UC_X86_REG_RSP,
)

DRIVER_SHA256 = "074c7425704bc61cab63ab61ff9c50dcae6eb0dd896c87b0e2f0c862e585aa34"
STACK = 0x20000000
HEAP = 0x30000000
STOP = 0x40000000


class Driver:
    def __init__(self, path: Path):
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != DRIVER_SHA256:
            raise ValueError(
                "Unsupported gfspi.dll: addresses require version 1.1.17.140"
            )
        self.pe = pefile.PE(data=data)
        self.base = self.pe.OPTIONAL_HEADER.ImageBase

    def wrap(self, psk: bytes, mode: int) -> tuple[bytes, bytes]:
        if len(psk) != 32 or mode not in (0, 1):
            raise ValueError("Expected a 32-byte synthetic key and mode 0 or 1")
        uc = Uc(UC_ARCH_X86, UC_MODE_64)
        uc.mem_map(self.base, (self.pe.OPTIONAL_HEADER.SizeOfImage + 4095) & ~4095)
        uc.mem_write(self.base, self.pe.get_memory_mapped_image())
        uc.mem_map(STACK, 0x200000)
        uc.mem_map(HEAP, 0x1000000)
        uc.mem_map(STOP, 0x1000)
        next_alloc = HEAP + 0x10000

        def hook(machine, address, _size, _data):
            nonlocal next_alloc
            rva = address - self.base
            if rva in (0x81ECC, 0x81198):  # malloc and calloc
                size = machine.reg_read(UC_X86_REG_RCX)
                if rva == 0x81198:
                    size *= machine.reg_read(UC_X86_REG_RDX)
                if not 0 < size <= 0x100000:
                    raise RuntimeError(f"Unexpected allocation: {size}")
                result = next_alloc
                next_alloc += (size + 31) & ~31
                if next_alloc > HEAP + 0x1000000:
                    raise RuntimeError("Emulated heap exhausted")
            elif rva in (0x811A0, 0x79F80):  # free and stack-cookie check
                result = 0
            else:
                return
            rsp = machine.reg_read(UC_X86_REG_RSP)
            ret = struct.unpack("<Q", machine.mem_read(rsp, 8))[0]
            machine.reg_write(UC_X86_REG_RAX, result)
            machine.reg_write(UC_X86_REG_RSP, rsp + 8)
            machine.reg_write(UC_X86_REG_RIP, ret)

        uc.hook_add(UC_HOOK_CODE, hook)

        def call(rva, *args):
            rsp = STACK + 0x1FF000 - 8
            uc.mem_write(rsp, struct.pack("<Q", STOP))
            registers = (UC_X86_REG_RCX, UC_X86_REG_RDX, UC_X86_REG_R8, UC_X86_REG_R9)
            for register, arg in zip(registers, args):
                uc.reg_write(register, arg)
            uc.reg_write(UC_X86_REG_RSP, rsp)
            uc.emu_start(self.base + rva, STOP, timeout=60_000_000, count=20_000_000)
            if uc.reg_read(UC_X86_REG_RIP) != STOP:
                raise RuntimeError("Emulation exceeded its execution limit")
            return uc.reg_read(UC_X86_REG_RAX) & 0xFFFFFFFF

        uc.mem_write(self.base + 0xEFEFC, struct.pack("<I", mode))
        call(0x6640 if mode == 0 else 0x5F30, HEAP)
        call(0x6950 if mode == 0 else 0x62C0, HEAP + 16)
        seed = bytes(uc.mem_read(HEAP, 32))
        uc.mem_write(HEAP + 0x100, psk)
        uc.mem_write(HEAP + 0x200, struct.pack("<I", 0x800))
        result = call(0x6C60, HEAP + 0x100, 32, HEAP + 0x1000, HEAP + 0x200)
        length = struct.unpack("<I", uc.mem_read(HEAP + 0x200, 4))[0]
        if result != 0 or length != 102:
            raise RuntimeError(f"Wrapping failed: status={result:#x}, length={length}")
        return seed, bytes(uc.mem_read(HEAP + 0x1000, length))
