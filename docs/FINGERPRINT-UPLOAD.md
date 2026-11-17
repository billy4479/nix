# GXFP5120: how the official driver uploads a key

Follow-up to [the initial investigation](FINGERPRINT.md). This traces the same
SHA-256-pinned Goodix `gfspi.dll` 1.1.17.140 from Microsoft Update Catalog.

## Result and scope

**The official driver's host-side upload path has now been reproduced and tested
in offline emulation, down to the buffers submitted for individual SPI writes.**
The tests execute the original packet-building, fragmentation, retry, response
parsing, and hash-comparison code against explicit mocks. No laptop connection,
real sensor, Windows installation, firmware, or authentication settings were used.

This establishes what a Linux implementation must send and check. It does **not**
establish what portatilo's MCU will accept, whether it is in the right initial
state, or whether a successful upload persists across power loss.

The key result is not a mysterious Windows-only upload API. The driver sends an
ordinary Goodix production command over its ITE SPI transport. Windows DPAPI
protects a separate host-cache field; the actual sensor key is wrapped as
previously documented.

## Call path

RVA means an offset from image base `0x180000000` in this exact DLL.

```text
production_psk_process                  0x0407d0
  production_check_psk_is_valid          0x03f99c
  production_write_key                  0x041460
    production_write_mcu                0x041d68
      send wrapper                      0x05e6ec
        SpiSendDataToDeviceLock         0x05f754
          SpiSendDataToDevice           0x05f0ac
            PeripheralWriteWrapper      0x01055c
              ITE_EC_SPI_WRITE          0x00fe78
                SPB/WDF request helper  0x012a50  <- intercepted here
  production_check_psk_is_valid          0x03f99c
```

The final helper normally constructs and submits a Windows SPB/WDF transfer.
In the experiment it only records the outgoing buffer in Python memory and
returns a simulated status. No OS transport or device handle is available.

## 1. Provisioning payload

The normal setup path generates a fresh 32-byte PSK and constructs two
little-endian TLVs, then pads the total payload to a four-byte boundary:

```text
u32 0xBB010002
u32 sealed_length + 8
bytes DPAPI-sealed host copy
bytes seed8

u32 0xBB010003
u32 102
bytes sensor wrapper[102]

zero padding
```

The 102-byte wrapper is the authenticated, encrypted form of the sensor key.
The DPAPI-sealed portion is a distinct, Windows-readable backup of that key.
The driver does not upload the raw 32-byte key as plain command payload.

For the offline fixture, a **fake** 200-byte DPAPI result plus eight-byte seed
produces a 328-byte aligned payload. The exact same native TLV builder also
serializes an empty sealed field if the DPAPI mock returns success with zero
output length: its payload becomes 128 bytes.

**The empty-field experiment proves host-side serialization only.** A real
Windows DPAPI operation was not performed, and acceptance of an empty field by
sensor firmware is still unknown. It is a candidate Linux-only representation,
not a tested provisioning recipe.

## 2. Goodix command framing

For provisioning payload `P`, the command is `0xe0`:

```text
u8  command = 0xe0                  # group 0x0e, subcommand 0
u16 length = len(P) + 1             # little-endian, includes checksum
bytes P
u8 checksum
```

The low eight bits of the sum of command, both length bytes, payload, and
checksum equal `0xaa`. This is a protocol checksum, not cryptographic protection.

The resulting inner message is put inside a message-pack envelope:

```text
u8  0xa0
u16 inner_message_length           # len(P) + 4, little-endian
u8  sum(previous three bytes) mod 256
bytes inner_message
```

The envelope is padded with zeroes to a multiple of four bytes. Those outer
padding bytes are not included in its length field. The inner command checksum
is enabled on the normal key-upload path; it is not replaced with `0x88`.

The upload is not a TLS application record. Its key protection comes from the
sensor wrapper inside `BB010003`, not an already-established TLS session.

## 3. ITE SPI fragmentation

Every SPI write starts with:

```text
cc f2 | u16 rolling_counter, little-endian | up to 252 bytes
```

The counter is incremented before each transfer, including retransmissions. It
wraps from `0xffff` to `0x0000`. It is not a payload length or a fixed `00 01`
magic value. A counter initially zero produces `01 00` in the first transfer.

The padded message-pack envelope is split across these transfers. Each transfer
is at most 256 bytes including its four-byte ITE prefix. The Goodix/message-pack
headers occur only in the first fragment; continuation fragments contain the
next bytes of the same message, with a new ITE prefix.

For the synthetic 328-byte payload, the original driver submits:

```text
write 1: 256 bytes
  cc f2 01 00 a0 4c 01 ed e0 49 01 02 00 01 bb d0 00 00 00 ...
write 2: 88 bytes
  cc f2 02 00 ...remaining message bytes...
```

For this multi-transfer case, it calls a 15 ms delay helper after each successful
fragment, including the last. A single-transfer case does not use that loop.
The experiment records requested delays; it does not actually sleep.

This is important for a future implementation: the reference Linux driver's
ordinary command write must not be assumed to implement this larger-upload
fragmentation and counter behavior.

## 4. Acknowledgement is not completion

There are separate incoming messages and checks:

1. **Command ACK.** The original decoder recognizes inner command `0xb0` with
   the acknowledged command in its payload. For example:

   ```text
   b0 03 00 e0 01 16
   ```

   This sets the acknowledgement flag for command `0xe0`. It is not evidence
   that the new key was installed successfully.

2. **Production completion.** A production reply is parsed into a shared result
   buffer and signals event slot 7. For a minimal success reply:

   ```text
   e0 02 00 00 c8
            ^^ status = 0
   ```

   `production_write_mcu` requires a successful send/wait result and a zero
   first status byte. A nonzero status fails the upload and prevents saving the
   local cache at that point. The original receive parser was separately
   exercised with valid ACKs, zero/nonzero completion statuses, and a corrupt
   checksum. The corrupt reply did not signal production completion.

3. **Post-upload hash verification.** Setup subsequently reads `BB020003` using
   command `0xe4`. The read request payload is:

   ```text
   03 00 02 bb 00 00 00 00
   ^ type      ^ zero field
   ```

   The response contains a status followed by a TLV holding the hash. The
   inspected DLL compares the 32-byte value against **SHA-256 of the 102-byte
   sensor wrapper**, not SHA-256 of the raw key. Native hash computation and
   matching/mismatching readback paths were exercised in emulation.

These examples are inner Goodix messages. They do not include the incoming
message-pack/ITE transport headers. The real IRQ-driven receive transport and
its electrical timing have not been emulated or validated on hardware.

## 5. Retry and error behavior

There are nested retry layers, not one universal two-attempt limit:

- `production_psk_process`: check an existing key up to twice before generating
  a replacement; attempt key creation/upload up to twice; check again after a
  successful upload. An initially valid key is not overwritten.
- `production_write_mcu`: retry the locked send once if it reports failure.
- Locked send: reset the production event, send, then poll completion in 50 ms
  waits for a 1,000 ms budget. On timeout it resends once and waits again.
- Command send: request a 500 ms ACK budget. Its first ACK wait is promoted to
  at least 1,000 ms, polling every 15 ms. On timeout it retransmits the command;
  the second ACK loop uses the original 500 ms budget.
- SPI failure during a fragmented command can restart the whole command at a
  higher layer. Retransmitted fragments carry fresh counters.

The offline tests confirmed these concrete cases for a single-transfer payload:

- ACK arrives only after a retransmission: two writes, one command-builder call.
- No ACK ever arrives: four writes across two command-builder calls, no
  production-event waits, failure `0xffdffffc`.
- ACK arrives but completion never does: four writes and eighty 50 ms wait
  requests across the nested send attempts, then the same failure.
- One SPI write fails: a retry can succeed. Persistent SPI failures fail the
  operation and do not save the local cache.
- A second-fragment SPI failure restarts the complete command, not just that
  fragment.
- A nonzero completion status fails without a transport retry inside
  `production_write_mcu`; the outer setup routine has its own retry policy.
- Upload acknowledgements followed by repeated hash mismatches do not make the
  outer setup routine report success.

These are driver behaviors with mocked outcomes, not evidence that retries are
idempotent or recoverable after a real interrupted flash write. A Linux tool
should not blindly repeat destructive commands after an uncertain response.

One other observed quirk: `production_write_key` does not propagate a local
cache-file write failure after a successful MCU write. A Linux implementation
should handle key persistence more carefully rather than reproduce that behavior.

## Offline artifacts and reproduction

- [`scripts/fingerprint/machine.py`](../scripts/fingerprint/machine.py): shared
  memory-only PE emulator. Imports are replaced by explicit mocks; unmocked
  imports fail. The stack-cookie hook preserves the return register, which is
  necessary for meaningful negative-path tests.
- [`scripts/fingerprint/upload.py`](../scripts/fingerprint/upload.py): packet
  model and upload experiment. SPI writes, randomness, DPAPI, cache files,
  events, locks, and time are simulated.
- [`scripts/fingerprint/verify_upload.py`](../scripts/fingerprint/verify_upload.py):
  20 test methods, including both wrapper branches, 19 payload sizes around
  fragmentation/padding boundaries, counter rollover, error/retry paths, the
  real reply parser, native SHA-256, and hash acceptance/rejection.

Run with the same DLL as the initial investigation:

```sh
nix shell --impure --expr '
  let p = (builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux;
  in p.python3.withPackages (ps: [ps.pefile ps.unicorn ps.cryptography])
' -c python scripts/fingerprint/verify_upload.py /path/to/gfspi.dll
```

The original wrapping checks remain available in `verify.py`. No proprietary
binary, real device key, real cache, or live upload utility is committed.

## What is still missing

The host-side bytes and checks are no longer the main unknown. Remaining work
would be to establish the actual MCU/firmware and ACPI/GPIO resources, implement
a safe ITE transport, and determine whether the firmware permits readback or a
Linux-only provisioning structure in its current state.

The offline host path does not require knowing the old PSK to construct and
send the replacement. **That does not prove the sensor will authorize it.**
Firmware acceptance, initial-state requirements, physical timing, persistence,
and recovery after interrupted writes cannot be established by mocking success
responses. No real hardware experiment was attempted.
