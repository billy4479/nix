"""Compare the official driver's upload path with an independent wire model.

Usage: python scripts/fingerprint/verify_upload.py /path/to/gfspi.dll
All keys, sealed blobs, acknowledgements, completion replies and SPI are fake.
No real Windows APIs or hardware are used, including on error/retry paths.
"""

import argparse
import hashlib
import struct
import unittest
from pathlib import Path

from emulate import Driver
from machine import HEAP
from upload import (
    FAKE_SEALED,
    TEST_KEY,
    TEST_SEED,
    Upload,
    message,
    parcels,
    provisioning,
)
from verify import SEEDS, wrap


class UploadTests(unittest.TestCase):
    driver = None

    def test_complete_key_upload(self):
        for mode, seed in enumerate(SEEDS):
            with self.subTest(mode=mode):
                trace = Upload(self.driver)
                trace.machine.write(trace.base + 0xEFEFC, struct.pack("<I", mode))
                self.assertEqual(trace.write_key(), 0)
                expected = provisioning(wrap(TEST_KEY, seed))
                self.assertEqual(len(expected), 328)
                self.assertEqual(trace.uploads, [expected])
                self.assertEqual(trace.writes, parcels(0xE0, expected))
                self.assertEqual([len(p) for p in trace.writes], [256, 88])
                self.assertEqual(trace.caches, [FAKE_SEALED + TEST_SEED])
                self.assertEqual(trace.commands, [(14, 0)])
                self.assertEqual(trace.waits, [50])
                self.assertEqual(trace.sleeps, [15, 15])

    def test_official_full_ite_read_sequence(self):
        machine = self.driver.machine()
        reads = []

        def capture_read(m):
            reads.append((m.read(m.arg(1), m.arg(2)), m.arg(4)))
            return 0

        machine.hooks[0x11178] = capture_read
        self.assertEqual(machine.call(0xFDE4, 99, HEAP, 256, 1), 0)
        self.assertEqual(reads, [(bytes.fromhex("bbf10000"), 256)])

    def test_official_state_request_and_wrapped_key_read(self):
        trace = Upload(self.driver)

        def system_time(machine):
            machine.write(
                machine.arg(0), struct.pack("<8H", 2026, 11, 1, 17, 12, 34, 12, 345)
            )
            return 0

        trace.machine.apis["GetLocalTime"] = system_time
        self.assertEqual(trace.machine.call(0x5CB68, HEAP + 0x1000), 1)
        self.assertEqual(trace.commands, [(10, 7)])
        state = parcels(0xAE, b"\x55\x39\x30\0\0")[0]
        # No-ACK bit is set after the checksum base is computed in this branch.
        state = state[:8] + bytes([state[8] | 1]) + state[9:]
        self.assertEqual(trace.writes, [state])

        trace = Upload(self.driver)
        data = bytes(range(102))
        trace.reply_data = struct.pack("<II", 0xBB010003, len(data)) + data
        trace.machine.write(HEAP + 0x2000, struct.pack("<I", 2048))
        self.assertEqual(
            trace.machine.call(0x41118, 0xBB010003, HEAP + 0x1000, HEAP + 0x2000), 0
        )
        self.assertEqual(trace.machine.read(HEAP + 0x1000, len(data)), data)
        self.assertEqual(trace.writes, parcels(0xE4, struct.pack("<II", 0xBB010003, 0)))

    def test_official_ite_version_query_is_only_a8(self):
        trace = Upload(self.driver)

        def forbid_reset(_):
            raise AssertionError("Version query attempted a reset/GPIO write")

        trace.machine.hooks[0xF878] = forbid_reset
        trace.machine.hooks[0xF914] = forbid_reset
        self.assertEqual(trace.machine.call(0x5C708, HEAP + 0x1000, 500), 1)
        self.assertEqual(trace.commands, [(10, 4)])
        self.assertEqual(trace.writes, parcels(0xA8, bytes(2)))
        self.assertEqual(trace.writes[0].hex(), "ccf20100a00600a6a803000000ff0000")

    def test_official_ite_hard_reset_path_does_not_touch_gpio_or_spi(self):
        trace = Upload(self.driver)

        def forbid_gpio(_):
            raise AssertionError("ITE path attempted a GPIO write")

        trace.machine.hooks[0xF878] = forbid_gpio
        self.assertEqual(trace.machine.call(0xF914, HEAP), 1)
        self.assertEqual(trace.commands, [])
        self.assertEqual(trace.writes, [])

    def test_valid_existing_key_is_not_overwritten(self):
        trace = Upload(self.driver)
        trace.machine.hooks[0x3F99C] = lambda _: 0
        self.assertEqual(trace.machine.call(0x407D0, HEAP), 0)
        self.assertEqual(trace.writes, [])
        self.assertEqual(trace.caches, [])

    def test_setup_validates_before_and_after_upload(self):
        trace = Upload(self.driver)
        results = [0xFFDFFFFC, 0xFFDFFFFC, 0]
        trace.machine.hooks[0x3F99C] = lambda _: results.pop(0)
        self.assertEqual(trace.machine.call(0x407D0, HEAP), 0)
        self.assertEqual(results, [])
        self.assertEqual(len(trace.uploads), 1)
        self.assertEqual(len(trace.caches), 1)

    def test_failed_post_upload_validation_is_not_success(self):
        trace = Upload(self.driver)
        checks = []

        def mismatch(_):
            checks.append(1)
            return 0xFFDFFFFC

        trace.machine.hooks[0x3F99C] = mismatch
        self.assertEqual(trace.machine.call(0x407D0, HEAP), 0xFFDFFFFC)
        self.assertEqual(len(checks), 4)
        self.assertEqual(len(trace.uploads), 2)
        self.assertEqual(len(trace.caches), 2)

    def test_packet_boundaries_and_padding(self):
        for length in (
            0,
            1,
            3,
            4,
            128,
            240,
            244,
            245,
            248,
            252,
            256,
            328,
            496,
            500,
            504,
            508,
            512,
            1024,
            2048,
        ):
            with self.subTest(length=length):
                trace = Upload(self.driver)
                payload = bytes(i % 256 for i in range(length))
                self.assertEqual(trace.send(payload), 0)
                self.assertEqual(trace.writes, parcels(0xE0, payload))
                self.assertTrue(
                    all(len(p) <= 256 and len(p) % 4 == 0 for p in trace.writes)
                )

    def test_counter_rollover(self):
        trace = Upload(self.driver)
        trace.machine.write(trace.base + 0xC4F40, struct.pack("<H", 0xFFFE))
        payload = bytes(512)
        self.assertEqual(trace.send(payload), 0)
        self.assertEqual(trace.writes, parcels(0xE0, payload, 0xFFFE))
        self.assertEqual(
            [p[2:4] for p in trace.writes], [b"\xff\xff", b"\0\0", b"\1\0"]
        )

    def test_ack_retry(self):
        trace = Upload(self.driver, ack_after=2)
        self.assertEqual(trace.send(bytes(128)), 0)
        self.assertEqual(trace.commands, [(14, 0)])
        self.assertEqual(len(trace.writes), 2)
        self.assertEqual(trace.writes[0][4:], trace.writes[1][4:])
        self.assertEqual(trace.writes[1][2:4], b"\2\0")
        self.assertEqual(trace.waits, [50])
        self.assertEqual(trace.sleeps, [15] * 67)

    def test_missing_ack(self):
        trace = Upload(self.driver, ack_after=None)
        self.assertEqual(trace.send(bytes(128)), 0xFFDFFFFC)
        self.assertEqual(len(trace.commands), 2)
        self.assertEqual(len(trace.writes), 4)
        self.assertEqual(trace.waits, [])
        self.assertEqual(len(trace.sleeps), 202)

    def test_completion_retry(self):
        trace = Upload(self.driver, completion_after=2)
        self.assertEqual(trace.send(bytes(128)), 0)
        self.assertEqual(len(trace.commands), 2)
        self.assertEqual(len(trace.writes), 2)
        self.assertEqual(trace.waits, [50] * 21)

    def test_missing_completion(self):
        trace = Upload(self.driver, completion_after=None)
        self.assertEqual(trace.send(bytes(128)), 0xFFDFFFFC)
        self.assertEqual(len(trace.commands), 4)
        self.assertEqual(len(trace.writes), 4)
        self.assertEqual(trace.waits, [50] * 80)

    def test_nonzero_status_rejected_without_transport_retry(self):
        trace = Upload(self.driver, status=1)
        self.assertEqual(trace.write_key(), 0xFFDFFFFC)
        self.assertEqual(len(trace.commands), 1)
        self.assertEqual(trace.caches, [])

    def test_failed_spi_write_retried(self):
        trace = Upload(self.driver, fail_write=1)
        self.assertEqual(trace.send(bytes(128)), 0)
        self.assertEqual(len(trace.commands), 2)
        self.assertEqual(len(trace.writes), 2)
        self.assertEqual(trace.waits, [50])

    def test_partial_upload_spi_failure_restarts_the_command(self):
        trace = Upload(self.driver, fail_write=2)
        payload = bytes(328)
        self.assertEqual(trace.send(payload), 0)
        self.assertEqual(len(trace.commands), 2)
        self.assertEqual(
            trace.writes, parcels(0xE0, payload) + parcels(0xE0, payload, 2)
        )

    def test_persistent_spi_failure_does_not_save_cache(self):
        trace = Upload(self.driver, fail_write=0)
        self.assertEqual(trace.write_key(), 0xFFDFFFFC)
        self.assertEqual(len(trace.commands), 2)
        self.assertEqual(len(trace.writes), 2)
        self.assertEqual(trace.waits, [])
        self.assertEqual(trace.caches, [])

    def test_empty_host_cache_field_can_be_serialized(self):
        trace = Upload(self.driver)

        def empty_seal(machine):
            machine.write(machine.arg(5), struct.pack("<I", 0))
            return 0

        trace.machine.hooks[0xBC34] = empty_seal
        self.assertEqual(trace.write_key(), 0)
        expected = provisioning(wrap(TEST_KEY, SEEDS[0]), sealed=b"")
        self.assertEqual(len(expected), 128)
        self.assertEqual(trace.uploads, [expected])
        self.assertEqual(trace.writes, parcels(0xE0, expected))
        # This demonstrates serialization only, NOT acceptance by real firmware.

    def test_cache_failure_not_propagated_by_official_driver(self):
        trace = Upload(self.driver)
        trace.cache_result = 0
        self.assertEqual(trace.write_key(), 0)
        self.assertEqual(trace.caches, [FAKE_SEALED + TEST_SEED])

    def test_original_ack_and_completion_decoder(self):
        trace = Upload(self.driver)
        trace.receive(0xB0, b"\xe0\1")
        self.assertEqual(trace.machine.uint(trace.base + 0xECC20 + 112 * 24, 1), 1)
        for status in (0, 1):
            trace.receive(0xE0, bytes([status]))
            self.assertEqual(trace.machine.uint(trace.base + 0xD8F88), 1)
            self.assertEqual(trace.machine.uint(trace.base + 0xD8F8C, 1), status)
            self.assertEqual(trace.events[-1], 8)

    def test_corrupt_reply_not_signalled_as_completion(self):
        trace = Upload(self.driver)
        frame = bytearray(message(0xE0, b"\0"))
        frame[-1] ^= 1
        trace.machine.write(HEAP, bytes(frame))
        trace.machine.call(0x606EC, HEAP, len(frame))
        self.assertNotIn(8, trace.events)
        self.assertIn(99, trace.events)

    def test_native_hash_is_sha256(self):
        trace = Upload(self.driver)
        wrapper = wrap(TEST_KEY, SEEDS[0])
        trace.machine.write(HEAP, wrapper)
        self.assertEqual(
            trace.machine.call(0x7380, HEAP, len(wrapper), HEAP + 0x1000), 0
        )
        self.assertEqual(
            trace.machine.read(HEAP + 0x1000, 32), hashlib.sha256(wrapper).digest()
        )

    def test_post_upload_hash_read_and_comparison(self):
        expected_hash = hashlib.sha256(wrap(TEST_KEY, SEEDS[0])).digest()
        for matches in (True, False):
            with self.subTest(matches=matches):
                trace = Upload(self.driver)

                def host_data(machine):
                    machine.write(machine.arg(0), TEST_KEY)
                    machine.write(machine.arg(2), expected_hash)
                    machine.write(machine.arg(4), FAKE_SEALED + TEST_SEED)
                    machine.write(
                        machine.arg(5), struct.pack("<I", len(FAKE_SEALED) + 8)
                    )
                    machine.write(machine.arg(6), b"\1")  # already cached
                    return 0

                trace.machine.hooks[0x3FEF0] = host_data
                remote_hash = expected_hash if matches else bytes(32)
                trace.reply_data = struct.pack("<II", 0xBB020003, 32) + remote_hash
                result = trace.machine.call(0x3F99C)
                self.assertEqual(result == 0, matches)
                request = struct.pack("<II", 0xBB020003, 0)
                self.assertEqual(trace.commands, [(14, 2)])
                self.assertEqual(trace.writes, parcels(0xE4, request))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("driver", type=Path)
    args = parser.parse_args()
    UploadTests.driver = Driver(args.driver)
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(UploadTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)
    print("All captured SPI writes and replies were simulated; no hardware accessed.")


if __name__ == "__main__":
    main()
