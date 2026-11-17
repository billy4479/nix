"""Offline verification of the GXFP5120 wrapping format against Windows code.

Usage: python scripts/fingerprint/verify.py /path/to/gfspi.dll
Requires cryptography, pefile, and unicorn. Uses only public synthetic test keys.
This is an investigation harness, not a sensor provisioning or key recovery tool.
"""

import argparse
import hashlib
import hmac
import struct
from pathlib import Path

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from emulate import Driver

SEEDS = (
    bytes.fromhex("5cba6e25819518de2d53e96dc0347ab0d427d4084bda4fae1bff2b09112a57e5"),
    bytes.fromhex("5cba6e251a74d4a32d53e96db764709ed427d4081a74d4a31bff2b09b764709e"),
)
HEADER = bytes.fromhex("02ff20000000")
AAD = struct.pack("<IIII", 0xF0C12D52, 0x077D5699, 0xA3377FF4, 0x7D42842A)


def derive(seed: bytes) -> tuple[bytes, bytes]:
    label = b"kgoodwixg\0kaelrgnoerlithm" + bytes.fromhex("00000180")
    rounds = [hmac.digest(seed, struct.pack(">I", i) + label, "sha256") for i in (1, 2)]
    return rounds[0], rounds[0][16:] + rounds[1][:16]


def wrap(psk: bytes, seed: bytes) -> bytes:
    if len(psk) != 32:
        raise ValueError("Expected a 32-byte test key")
    iv = hashlib.sha256(HEADER + psk[:8] + struct.pack("<I", 3) * 16).digest()[:16]
    aes_key, mac_key = derive(seed)
    encrypted = AESGCM(aes_key).encrypt(iv, psk, AAD)
    mac = hmac.digest(mac_key, HEADER + encrypted, "sha256")
    return mac + HEADER + iv + encrypted


def unwrap(blob: bytes, seed: bytes) -> bytes:
    if len(blob) != 102 or blob[32:38] != HEADER:
        raise ValueError("Invalid wrapper")
    aes_key, mac_key = derive(seed)
    expected_mac = hmac.digest(mac_key, blob[32:38] + blob[54:], "sha256")
    if not hmac.compare_digest(blob[:32], expected_mac):
        raise ValueError("Invalid HMAC")
    return AESGCM(aes_key).decrypt(blob[38:54], blob[54:], AAD)


def require(condition: bool, message: str):
    if not condition:
        raise AssertionError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("driver", type=Path, help="Unmodified gfspi.dll 1.1.17.140")
    args = parser.parse_args()
    driver = Driver(args.driver)
    keys = (
        bytes(32),
        bytes(range(32)),
        bytes([255]) * 32,
        hashlib.sha256(b"gxfp5120 offline test").digest(),
    )
    comparisons = 0
    rejections = 0
    for mode, expected_seed in enumerate(SEEDS):
        for index, psk in enumerate(keys):
            seed, blob = driver.wrap(psk, mode)
            require(seed == expected_seed, "Unexpected runtime seed")
            require(blob == wrap(psk, seed), "Windows/Python wrapping mismatch")
            require(unwrap(blob, seed) == psk, "Authenticated round trip failed")
            for position in (0, 32, 38, 54, 101):
                bad = bytearray(blob)
                bad[position] ^= 1
                try:
                    unwrap(bytes(bad), seed)
                except (ValueError, InvalidTag):
                    rejections += 1
                else:
                    raise AssertionError(f"Tampering accepted at byte {position}")
            comparisons += 1
            print(f"mode={mode} vector={index}: exact match and authenticated recovery")
    print(f"{comparisons} Windows/Python comparisons; {rejections} tamper rejections.")
    print("No hardware accessed; no device keys generated or changed.")


if __name__ == "__main__":
    main()
