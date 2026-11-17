"""Closed, in-memory PE emulation for offline driver experiments.

Imports never resolve to host APIs. Every used import needs an explicit Python
mock; unknown imports fail. There is no device or filesystem transport here.
"""

import struct

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

STACK = 0x20000000
HEAP = 0x30000000
STOP = 0x40000000
IMPORTS = 0x50000000
REGISTERS = (UC_X86_REG_RCX, UC_X86_REG_RDX, UC_X86_REG_R8, UC_X86_REG_R9)


class Machine:
    def __init__(self, pe):
        self.base = pe.OPTIONAL_HEADER.ImageBase
        self.uc = Uc(UC_ARCH_X86, UC_MODE_64)
        self.uc.mem_map(self.base, (pe.OPTIONAL_HEADER.SizeOfImage + 4095) & ~4095)
        self.uc.mem_write(self.base, pe.get_memory_mapped_image())
        for address, size in (
            (STACK, 0x200000),
            (HEAP, 0x1000000),
            (STOP, 0x1000),
            (IMPORTS, 0x10000),
        ):
            self.uc.mem_map(address, size)
        self.next_alloc = HEAP + 0x10000
        self.hooks = {}
        self.apis = {}
        self.imports = {}
        for descriptor in pe.DIRECTORY_ENTRY_IMPORT:
            for entry in descriptor.imports:
                address = IMPORTS + len(self.imports) * 16
                self.imports[address] = (
                    entry.name.decode() if entry.name else f"ordinal_{entry.ordinal}"
                )
                self.uc.mem_write(entry.address, struct.pack("<Q", address))
        self.uc.hook_add(UC_HOOK_CODE, self._hook)

    def read(self, address, size):
        return bytes(self.uc.mem_read(address, size))

    def write(self, address, data):
        self.uc.mem_write(address, data)

    def uint(self, address, size=4):
        return int.from_bytes(self.read(address, size), "little")

    def arg(self, index):
        if index < 4:
            return self.uc.reg_read(REGISTERS[index])
        return self.uint(self.uc.reg_read(UC_X86_REG_RSP) + 0x28 + (index - 4) * 8, 8)

    def _return(self, result):
        rsp = self.uc.reg_read(UC_X86_REG_RSP)
        target = self.uint(rsp, 8)
        self.uc.reg_write(UC_X86_REG_RAX, result & 0xFFFFFFFFFFFFFFFF)
        self.uc.reg_write(UC_X86_REG_RSP, rsp + 8)
        self.uc.reg_write(UC_X86_REG_RIP, target)

    def _hook(self, _uc, address, _size, _data):
        rva = address - self.base
        if rva in self.hooks:
            result = self.hooks[rva](self)
            if result is None:  # Observe entry, then execute original code.
                return
        elif address in self.imports:
            name = self.imports[address]
            if name not in self.apis:
                raise RuntimeError(f"Unmocked Windows import: {name}")
            result = self.apis[name](self)
        elif rva in (0x81ECC, 0x81198):
            size = self.arg(0)
            if rva == 0x81198:
                size *= self.arg(1)
            if not 0 < size <= 0x100000:
                raise RuntimeError(f"Unexpected allocation: {size}")
            result = self.next_alloc
            self.next_alloc += (size + 31) & ~31
            if self.next_alloc > HEAP + 0x1000000:
                raise RuntimeError("Emulated heap exhausted")
        elif rva == 0x811A0:  # free
            result = 0
        elif rva == 0x79F80:  # Stack-cookie helper preserves the return register.
            result = self.uc.reg_read(UC_X86_REG_RAX)
        else:
            return
        self._return(result)

    def call(self, rva, *args):
        rsp = STACK + 0x1FF000 - 8
        self.write(rsp, struct.pack("<Q", STOP))
        for index, register in enumerate(REGISTERS):
            self.uc.reg_write(register, args[index] if index < len(args) else 0)
        for index, arg in enumerate(args[4:]):
            self.write(rsp + 0x28 + index * 8, struct.pack("<Q", arg))
        self.uc.reg_write(UC_X86_REG_RSP, rsp)
        self.uc.emu_start(self.base + rva, STOP, timeout=60_000_000, count=20_000_000)
        if self.uc.reg_read(UC_X86_REG_RIP) != STOP:
            raise RuntimeError("Emulation exceeded its execution limit")
        return self.uc.reg_read(UC_X86_REG_RAX) & 0xFFFFFFFF
