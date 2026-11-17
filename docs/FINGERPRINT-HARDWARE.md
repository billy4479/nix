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

### An interrupt candidate, not a confirmed mapping

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

This is a strong candidate, **not proof that `GFPI` resolves to 279**. A matching
pad configuration cannot replace the runtime firmware resource. No line was
requested, no interrupt was installed, and no finger/event experiment was done.
The output/control GPIO remains unidentified.

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

No workaround using `/dev/mem`, physical-memory probing, kernel-module loading,
ACPI method execution, GPIO requests, driver binding, or SPI commands was
attempted. In particular, loading the dumped tables into an offline interpreter
with zero-filled GNVS would not recover the real pin numbers.

## Consequences for bring-up

- The declared SPI speed, mode and interrupt polarity agree with the ITE
  reference transport. This is useful evidence, not a completed communication
  test.
- The GPIO mapping cannot safely be treated as the reference machine's mapping.
  The runtime `_CRS` or its GNVS inputs should be obtained before using GPIOs.
- A resource-query helper would need to be narrowly reviewed and scoped to
  reading those resources, not calling `_INI` or configuring pins. The current
  kernel lacks the straightforward debugger interface; changing the kernel or
  loading a helper would be a separate step, not something done in this passive
  inspection.
- After the wiring is confirmed, the first sensor transaction should identify
  firmware/status without provisioning. A rising-edge candidate and a compatible
  ACPI ID do not authorize a key upload.

**Bottom line:** the archive confirms the SPI wiring and exposes an important
GPIO portability issue. Exact runtime GPIO assignment, MCU identity, readback
permissions and Linux-only key acceptance remain unverified.
