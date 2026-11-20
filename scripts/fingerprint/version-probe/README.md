# Firmware-version-only SPI probe

This is the first live sensor-communication step, not another passive resource
query. It sends one fixed Goodix firmware-version command (`0xa8`) and polls the
ITE response window. It has no reset, preamble, handshake, scan, enrollment,
configuration-upload, key-write, arbitrary-command, or fallback interface.

## Run on portatilo

Place the reviewed bundle at `/home/billy/fingerprint-version-probe`. If it
arrives as a download, extract it into your home directory first:

```sh
tar -xzf ~/Downloads/fingerprint-version-probe.tar.gz -C ~
sudo ~/fingerprint-version-probe/run.sh
```

Return the printed `~/fingerprint-version-report.*.txt` path, whether the query
succeeds or not. Do not run it repeatedly to chase a response or continue after
a cleanup warning. Raw reply windows are kept in the private, user-owned report,
not printed in full to the terminal. Unexpected queued responses could contain
sensitive information; do not publish the report.

## Scope and guards

The runner verifies its bundle checksums, the exact running kernel release/store
path, and the previously reviewed DSDT hash. It refuses a bound fingerprint
device or a pre-existing driver override. A lock prevents concurrent runs.

It loads the kernel's ordinary `spidev` module if needed, temporarily overrides
and binds only `spi-GXFP5120:00`, then discovers the matching character device
by its sysfs parent, rather than assuming a `/dev/spidev*` number. The binary
also validates the opened character device's sysfs identity before any SPI ioctl.
The SPI-NOR flash at `spi0.0` is never selected.

After the probe, including ordinary errors/timeouts, the exit trap attempts to
unbind the fingerprint device, clear its override, and unload `spidev` if this
run loaded it. It verifies the target is unbound and the override is cleared,
and records SPI counters before/after. This does not install a driver or change
boot configuration.

The userspace program opens no GPIO device and requests no GPIO lines. In
particular it never drives GPIO 0. **Binding can still let Linux's SPI/ACPI core
resolve and configure the declared interrupt input**, as during normal device
enumeration. On this machine that resource is GPIO 279. Do not interpret the
absence of userspace GPIO calls as a guarantee that every controller register
remains untouched. SPI transfers necessarily change volatile controller/EC
state and consume response data; they are not a passive file read.

## Exactly what is sent

The single 16-byte version request is:

```text
cc f2 01 00 a0 06 00 a6 a8 03 00 00 00 ff 00 00
```

It is identical to the original driver's ITE `GetEvkVersion` output, verified
in offline emulation with reset/GPIO calls forbidden. No NOP/preamble is added.

The probe uses the ACPI-declared mode 0, 8-bit words, and 10 MHz maximum clock.
It then performs small polling reads, the same response-window form used by
the reference ITE transport: `bb f1 00 00` followed by 60 zero bytes. It requests
at most 128 windows, with a 1.5-second loop deadline and short delays. The runner
adds a 15-second process timeout and a two-second kill grace period. These bound
userspace execution; they cannot guarantee a broken kernel I/O request is
interruptible or eliminate hardware bring-up risk.

A firmware string is accepted only from a correctly framed `0xa8` reply with
both header and inner-message checksum validation and bounded printable ASCII
content. An ACK by itself is not a version. The unchecked `0x88` checksum marker
is not accepted as a substitute for a valid checksum. ACK receipt is reported
separately.

Possible results:

- Exit 0 / `result=version_received`: a valid version reply was parsed.
- Exit 2 / `result=no_valid_version`: stop and inspect the report. This could be
  silence, an incompatible transport/format, or an unready sensor; it does not
  establish lack of support.
- Exit 1 or a timeout: inspect the error and cleanup fields before doing more.

No sensor key or persistent firmware/configuration write is performed. The first
user-run test on portatilo, kernel `7.3.5-zen1`, returned `GF_ITE_EC_20066` with a
valid ACK, no SPI errors/timeouts, and successful binding/override cleanup. This
validates the version exchange only, not TLS, imaging or provisioning.

## Build and tests

From the repository root:

```sh
nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake (toString ./.);
      host = f.nixosConfigurations.portatilo;
  in host.pkgs.pkgsStatic.callPackage ./scripts/fingerprint/version-probe {
    kernel = host.config.boot.kernelPackages.kernel;
  }
'
```

The binary is statically linked. It shares guarded SPI I/O helpers in `../spi`
with the separate readback tool, but this entrypoint still sends only one A8.
The shared runner defaults to version-only; a checksum-manifested `probe-kind`
file is required to select the separate readback executable.

The build runs protocol tests covering the
exact outgoing query, every frame split, bytewise delivery, malformed lengths
and checksums, noise, ACK-only input, unrelated commands, maximum string length,
buffer bounds, invalid/embedded-NUL text, and sanitized ACK/version frames from
the successful live query. They do not simulate real electrical
SPI timing or test Linux's live driver-binding/cleanup path. The runner is
syntax-checked and ShellCheck-checked.

`../verify_upload.py` additionally emulates the original Windows version-query
routine and compares its outgoing SPI bytes, while forbidding reset/GPIO calls.
