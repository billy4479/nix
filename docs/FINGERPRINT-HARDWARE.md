# Portatilo fingerprint wiring: passive inspection

This records analysis of the private archive collected by
[`collect-passive.sh`](../scripts/fingerprint/collect-passive.sh) on portatilo.
See [the overall investigation](FINGERPRINT.md) and
[the official upload protocol](FINGERPRINT-UPLOAD.md) for context.

## Scope and evidence

The snapshot was collected on 2026-11-17 with kernel `7.2.15-zen1`. Collection
reported no errors. Its DSDT and eleven SSDTs all have valid lengths and ACPI
checksums. Tables were decoded locally with ACPICA `iasl` 20260930, without
executing firmware methods or changing anything on the laptop.

A combined namespace disassembly encountered duplicate/unresolved objects, so
the tables were also decoded individually. The fingerprint device and its
helpers decoded successfully in DSDT; none of the SSDTs reference `GFPI`,
`GFPS`, `FPAD`, or `FPNT`. Disassembler namespace warnings are not a hardware
failure diagnosis.

Raw dumps remain private and outside Git. Snapshot identifiers:

```text
Archive SHA-256:
fa29994b0f9de2dcff6611aa99152f4fbefd27943c52062ba7e56a62dda561ba
DSDT SHA-256:
01654ee28ce0d6054b2dfdc93ce33a06947fe866d97617b8740c1eeb264347bb
```

## Confirmed transport

The device is `GXFP5120`, ACPI path `\_SB_.PC00.SPI1.FPNT`, on a HUAWEI
`BOD-WXX9` with Intel Core i5-1135G7. Its Linux SPI controller is PCI
`0000:00:1e.3` (`8086:a0ab`), exposed as `spi1`. The sensor is
`spi-GXFP5120:00`, chip select zero, and has no bound driver.

Its `_CRS` declares:

| Setting | Firmware declaration |
| --- | --- |
| SPI speed | 10,000,000 Hz (`0x00989680`) |
| Clock polarity/phase | Low / first edge: mode 0 |
| Chip select | 0, active low |
| Bus / word | Four-wire, controller-initiated, 8-bit |
| Interrupt | Edge-triggered, active high, exclusive and wake-capable |
| Additional GPIO | Output-only, pull-up, exclusive |
| GPIO controller | `\_SB.GPI0`, enumerated as `INT34C5:00` / `/dev/gpiochip0` |

The pin snapshot shows GSPI1 CS, clock, MISO and MOSI in native mode 1, with
firmware locking. That is consistent with the declared bus and not a reason to
remux pins manually.

The controller was runtime-suspended. Both the sensor and `spi1` statistics
showed zero messages, transfers, transmitted/received bytes, errors and timeouts.
This means no Linux SPI transfers were recorded since registration; it says
nothing about factory initialization or earlier boot environments.

**`spi0.0` is a different device:** system SPI-NOR on PCI `0000:00:1f.5`.
No spidev node exists for the sensor yet. Do not bind or access the flash as a
fingerprint device, or assume the reference `/dev/spidev0.0` path applies.

## Important: the GPIO numbers are dynamic

The resource template initially contains GPIO pins `0` and `8`, but `_CRS`
replaces them before returning the resources:

```text
interrupt pin = GNUM(GFPI)
output pin    = GNUM(GFPS)
```

These are not static assignments in DSDT. `GFPS` and `GFPI` are 32-bit fields in
firmware-owned GNVS memory, at relative byte offsets `0x465` and `0x469`.
The archive contains the field definitions, not their runtime contents.

`GNUM` converts the firmware's encoded group/pad identifier into the ACPI GPIO
number using the platform's GPIO-group table. It is not correct to interpret
the raw encoded value directly as a Linux line number.

The device `_INI` calls `SHPO` on these two identifiers. Inspection of `SHPO`
shows that it updates GPIO host-software ownership bits. Those calls are **not**
evidence of a reset pulse or output level being driven. The purpose and active
polarity of the output-only line have not been established.

The reference driver's GPIO offset `17` must not be copied here. In this
snapshot offset 17 corresponds to the `GSPI0_MISO` pad, which is fully locked
and disabled as a GPIO input. Firmware resource confirmation is needed rather
than reuse of a different laptop's constant.

### Passive interrupt candidate, later confirmed

There is one GPIO-mode pad in the captured pin list with all of these settings:
input enabled, output disabled, single-edge detection, and no RX inversion.
It is:

```text
hardware pin: 194, pad name UART2_CTSB
GPIO character-device line offset: 279
PADCFG0: 0x82000100
```

These settings are consistent with the declared rising-edge interrupt. The
captured GPIO range maps hardware pins 171..194 to the corresponding GPIO
range; the `pins` file directly reports this pad's line offset as 279.
Intel pad names describe the possible native function, not necessarily what
is wired to that pad when used as GPIO.

At this stage it was a strong candidate, not proof of the firmware assignment.
The subsequent runtime query below confirmed it. No line was requested, no
interrupt was installed, and no finger/event experiment was done.

## Other firmware data and the current limit

The fingerprint device defines a device-specific method with UUID
`cc58b68a-4479-4893-a8bb-961209db59e5`. Function 1 exposes a 2,048-byte buffer
from firmware memory via the `FPAD` pointer. Neither the pointer's runtime
value nor the buffer contents were collected. This is not evidence that the
buffer contains a key, firmware version, or biometric data.

A separate unprivileged configuration check confirmed:

```text
# CONFIG_ACPI_DEBUGGER is not set
CONFIG_ACPI_DEBUG=y
CONFIG_PINCTRL_TIGERLAKE=m
```

Thus the running kernel does not provide the ACPI debugger needed for a simple
`acpidbg` query of the runtime fields/resources. The public ACPI table-data
directory is empty. The snapshot does not reveal the actual MCU firmware
version or any provisioning state.

During the passive archive analysis, no `/dev/mem` access, physical-memory
probing, kernel-module loading, ACPI method execution, GPIO request, driver
binding, or SPI command was attempted. Loading the dumped tables into an
offline interpreter with zero-filled GNVS would not recover the real pin numbers.

## Runtime query result

The user subsequently ran the [fixed-path ACPI helper](../scripts/fingerprint/acpi-resources/README.md)
on portatilo, after tests in three diskless QEMU guests. Its kernel and reviewed
DSDT checks passed. The actual returned resources are:

- SPI: select 0, 10 MHz, 8-bit, mode 0, active-low CS, four-wire.
- GPIO interrupt: `\_SB.GPI0`, **line 279**, edge-triggered, active high,
  exclusive, wake-capable. This confirms the passive candidate.
- GPIO I/O: `\_SB.GPI0`, **line 0**, output-only, pull-up.

The helper unloaded successfully. All six sensor SPI counters remained zero
before and after the query. Kernel taint changed from 8192 to 12288: the usual
out-of-tree-module bit was added; the unsigned-module bit was already present.

**Do not drive GPIO 0.** Its resource assignment is now known, but its intended
role is not. The earlier snapshot shows this offset as the locked native
`CORE_VID_0` pad. It could be an unused/default resource; that is not established.
The generic `polarity=1` field of a GPIO-I/O descriptor is not evidence of an
active-low reset line.

Additional inspection of the official DLL found that `HardResetMcu` at RVA
`0x00f914` deliberately returns success without GPIO or SPI activity for project
type 1, the ITE path. This branch was exercised in offline emulation with GPIO
writes forbidden. It supports leaving the output resource alone for the initial
version query; it does not prove that all driver paths ignore it. The official
version-retry routine must not be copied wholesale as a supposedly passive probe.

## First live sensor query succeeded

After updating to kernel `7.3.5-zen1`, the user ran the rebuilt
[firmware-version probe](../scripts/fingerprint/version-probe/README.md).
It bound the fingerprint device temporarily at `/dev/spidev1.0`, sent one
fixed `0xa8` query and polled two ITE response windows. The report shows:

```text
firmware=GF_ITE_EC_20066
ack_seen=yes
valid_frames=2
rejected_frames=0
probe_exit=0
cleanup_failed=0
driver_override_after=empty
fingerprint_unbound=yes
```

Both the ACK and version frames passed independent message-pack and inner
checksum validation. Only those short, non-secret frames were added as a
parser regression fixture; the private raw windows and their unrelated trailing
bytes are not committed.

The SPI counters recorded three messages/transfers, 144 transmitted bytes and
128 received bytes, with zero errors/timeouts. Those correspond to the 16-byte
version command and two 64-byte polling reads. Cleanup was also verified over
SSH: the sensor was unbound and its driver override was empty. No userspace
GPIO request, reset, scan, sensor-configuration upload or key write occurred.
Linux's normal SPI/ACPI core may resolve the interrupt input during binding;
this is not a promise that all volatile controller state remained untouched.

**Firmware difference:** this unit reports `GF_ITE_EC_20066`, while the pinned
community project's reference machine reports `GF_ITE_EC_20063`. That is not
proof of incompatibility, but it does mean we must not assume the reference's
sensor die, calibration/configuration frame, or provisioning policy applies.
No exact `20066` reference was found in the already-inspected community sources.

## First key-discovery run: hash returned, parser too strict

The user ran readback v1 on `7.3.5-zen1`. It reported `mcu_state=no_reply` and
`result=hash_unavailable`, then stopped before requesting the wrapped key.
Cleanup succeeded, with no SPI errors/timeouts. SSH confirmed the sensor was
unbound again and its driver override was empty.

Private inspection of the archive found a successful, checksum-valid reply:

```text
request_opcode=E4
requested_selector=BB020003
response_opcode=E4
response_status=0
returned_object_tag=BB010003
declared_data_bytes=32
```

V1 incorrectly required the returned tag to echo the hash selector. This
firmware identifies the stored key object instead. Original-driver emulation
confirms that the OEM production reader accepts this exact selector/tag pair.
The returned digest is retained privately; no digest bytes or raw windows are
committed or displayed. A digest alone does not establish the live PSK or its
recoverability.

The capture also shows a cached A8 version frame before the new A8 ACK and
version reply, and repeated older frames during idle polling. Those are not
new status replies. No `AE` MCU-state reply was captured; this does not establish
TLS/lock state or justify initialization/reset/configuration writes.

### Corrected v2: hash collected, no key wrapper returned

The [v2 readback probe](../scripts/fingerprint/readback-probe/README.md) leaves
MCU-state probing paused and sends only A8, E4/hash and E4/wrapped-key requests.
It requires ACK-then-version ordering for the observed `GF_ITE_EC_20066`, accepts
only the known hash selector/object tags, and ignores a repeated 32-byte hash
while waiting for a key wrapper. Other tags remain rejected. The successful
full-mailbox transport is unchanged rather than speculatively altering SPI.

Offline replay of the private capture verifies both fixes: the cached version
is ignored until ACK, and the returned 32-byte digest is recognized. Committed
regressions use synthetic data, not the real digest. Native-driver checks,
ASan/UBSan parser/flow tests and fake-filesystem archive/privacy/cleanup tests
also pass. No additional live queries have been run by the agent.

The user subsequently ran v2 on the same kernel. It received ACK then version,
collected a 32-byte hash matching v1, and attempted `BB010003` readback. That
request received another E4 ACK followed by a status-zero `BB010003` reply with
32 bytes identical to the hash. No 102-byte wrapper or different key material
was found in the complete, checksum-valid captured frames. The parser correctly
did not treat this digest as a recovered key:

```text
profile=ite-20066-key-readback-v2
mcu_state=not_requested
firmware=GF_ITE_EC_20066
key_hash=collected
result=wrapped_key_unavailable
probe_exit=2
cleanup_failed=0
fingerprint_unbound=yes
driver_override_after=empty
```

There were zero SPI errors/timeouts. SSH independently confirmed cleanup. A
synthetic fake-sensor regression covers the same hash-only reply after ACK,
ensuring no wrapped-key file is created and no success is reported. Offline
replay also exposed a poll-boundary issue: carrying a trailing partial frame
into the next mailbox window could hide its new ACK. Resetting pending bytes
per poll preserves that ACK, but still yields no key from this capture. The
SPI transport and transmitted requests are unchanged; no repeat run is needed.
A synthetic partial-frame/new-ACK regression covers this correction. Checked
public reference/default digests and SHA-256 of an empty object did not match;
this is not an exhaustive search or proof of a particular stored-key format.

This is not an explicit access refusal, nor proof that every possible recovery
route is closed. It establishes that these reviewed selectors did not export a
usable key. Do not keep rerunning them. No actual PSK has been recovered, and no
persistent sensor write has been attempted. The private mode-0600 archive and
all response data remain outside Git/Nix.

A possible Linux-only next step is to provision a newly generated key using the
already analyzed OEM upload path. That changes persistent sensor state and
requires separate explicit approval and manual execution. The old key has not
been backed up, so rollback cannot be promised. Firmware acceptance and
persistence remain untested; keep password authentication.

### First provisioning preflight: hash timed out before any write

The user ran provisioning v2 on `7.3.5-zen1`. Firmware `GF_ITE_EC_20066`
responded, but the probe exited `existing_hash_unavailable_stop` after the
hash poll budget. The SPI counters recorded no errors or timeouts, and cleanup
restored the unbound state. This exit happens before key generation or upload.
The summary did not record hash frames on timeout, so it cannot tell us whether
an ACK or a misparsed reply was present. Use the readback bundle's new
`--check-hash` mode to capture the same version/hash requests without any
wrapped-key query, upload, or fallback. Keep its archive private.

The diagnostic succeeded: the first hash window had no valid reply, the
second had the matching ACK, and the third had a valid digest. Provisioning v3
now preserves ACK state across windows and reports hash counters even on
preflight timeout. It also keeps one rolling ITE transmit counter across the
preflight, upload and verification instead of resetting it at upload. This
corrects an offline finding, not a demonstrated cause of the v2 timeout.

Provisioning v3 also stopped before key generation. It counted 108 valid
frames during the hash wait but saw neither a matching hash ACK nor a hash
reply; SPI again reported no errors. V4 gives the MCU a short settling interval
after the version reply and repeats a wholly unanswered hash read at most once,
with a fresh counter. It still requires the hash ACK and valid digest before
attempting an upload, and it never retries an upload.

## Consequences for bring-up

- The declared mode-0/10 MHz ITE transport now has a successful live version
  exchange. This does not yet validate TLS, image capture or authentication.
- Use the confirmed interrupt offset 279, not the reference driver's offset 17.
  Do not request the declared output offset 0 as a reset/control line.
- The resource query required no kernel replacement and made no SPI transfers.
  It did not identify the MCU or inspect provisioning data.
- V2 completed the approved hash/wrapped-key queries without recovering a key.
  MCU-state probing stays paused. Further offline analysis is possible; persistent
  key replacement needs its own explicit approval, not another readback retry.
  Any returned device-specific data must remain private, not in Git.

**Bottom line:** live communication, firmware revision, key-hash readback and
interrupt assignment are confirmed. The output resource is unsafe to assume
usable. The reviewed key-read query returned only the hash. Sensor-die identity,
provisioning policy, the live key, TLS and scanning remain unverified.
