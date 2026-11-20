# Portatilo: private, read-only MCU/key readback

Prepared for a separate manual sudo run. No live queries are run during build or
delivery. This is not an authentication driver, initialization script or key
provisioner.

## Fixed command allowlist

In order, without command retries:

1. `A8`, two zero bytes: require exactly `GF_ITE_EC_20066`, the firmware already
   observed on this machine. Stop on any different/unavailable version.
2. `AF`, `55 <milliseconds-within-minute:LE16> 00 00`: the official driver's
   no-ACK MCU-state request, expecting an `AE` reply with 20 bytes. The ITE
   branch computes the inner checksum before adding the no-ACK bit. A timeout
   is advisory: the two independent, already-approved read requests below still
   run. I/O/malformed/unexpected-layout errors stop instead. State flags do not
   establish permission to change keys.
3. `E4`, `BB020003:LE32 00000000`: read existing key-wrapper hash. Require status
   zero, the matching type, exact declared length, and 32 data bytes. Stop on
   refusal, timeout, malformed data or an unexpected size, without attempting
   wrapped-key readback.
4. `E4`, `BB010003:LE32 00000000`: read the existing wrapped key. Save a
   checksum-valid, correctly tagged response privately. Expect the previously
   analyzed 102-byte format with header `02ff20000000` at offset 32; preserve an
   unexpected format for inspection but report exit 2 rather than success.

`BB010002` (Windows host backup) is not requested. There is no arbitrary command,
tag, payload, offset or length CLI, and no `E0` provisioning command, reset,
configuration, TLS, GPIO request, image acquisition, enrollment, key generation
or fallback path. These reads necessarily affect volatile EC/SPI state; they
are not a claim that the whole device remains electrically untouched.

The state request, wrapped-key read and `bb f1 00 00` write/read operation were
checked against original `gfspi.dll` machine code using simulated Windows APIs
and SPI. The same production-read function supplies the previously verified
`BB020003` hash request. This validates host encoding, not this firmware's
readback permission or persistence policy.

## Transport and privacy

Uses the same strict character-device/sysfs identity checks as the successful
version probe: only `spi-GXFP5120:00` under PCI `00:1e.3`. SPI mode 0, 8-bit,
requested 10 MHz. Do not target system flash `spi0.0` / PCI `00:1f.5`.

A wrapped-key record cannot fit in the first probe's 60-byte response window.
Readback instead uses a single two-transfer SPI message: four command/status
bytes followed by the reference ITE transport's full 256-byte mailbox, with CS
kept asserted between transfers. Both message-pack and inner checksums are
required, including across multiple mailboxes, with at most 2048 data bytes.
The unchecked `88` checksum shortcut is not accepted. Unrelated reply tags and
ACKs cannot substitute for a requested data reply.

Each query has at most 128 polls / 1.5 seconds. The runner bounds the subprocess
at 15 seconds plus a two-second kill grace. Kernel I/O is not guaranteed to be
interruptible; timeouts cannot eliminate hardware bring-up risk.

The shared runner retains kernel-path/release and DSDT-hash guards, exclusively
locks against the earlier version probe, binds only the unbound fingerprint
device, restores its override/binding, and unloads spidev if newly loaded.
No guard should be bypassed after a firmware/kernel change.

Raw replies, including unrelated mailbox tails, can contain sensitive data.
They and the parsed replies are written only inside the runner's private,
executing-user-owned directory, with mode 0600 and exclusive/no-symlink file
creation. The probe disables process dumpability before collecting replies.
Output is archived into:

```text
~/fingerprint-readback-report.XXXXXXXX.tar.gz
```

The archive is mode 0600, owned by the invoking user, and includes the report,
raw SPI log and any collected `mcu-state.bin`, `key-hash.bin`, `wrapped-key.bin`.
Terminal output contains only fixed firmware text, state flags and result/status
metadata, never key/hash bytes. Keep the archive out of Git, the Nix store and
public uploads. Return only its path; retrieve it privately over SSH.

Collection does **not** verify the wrapper's HMAC/GCM tag, correlate its SHA-256
with the returned digest, or decrypt a live PSK. Those are separate offline
steps. An empty/refused read is not evidence that provisioning is safe or that
no key exists. Stop and inspect the archive on any error; do not retry blindly.

## Build and run

From the repository root:

```sh
nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake (toString ./.);
      host = f.nixosConfigurations.portatilo;
  in host.pkgs.pkgsStatic.callPackage ./scripts/fingerprint/readback-probe {
    kernel = host.config.boot.kernelPackages.kernel;
  }
'
```

The result is a complete, checksum-manifested bundle, including reviewed source,
the static executable, shared runner and kernel identity metadata. Copy its
contents into a private directory on portatilo, not through a Nix derivation
that reads live secrets. Review the source before running manually:

```sh
sudo ~/fingerprint-readback-probe/run.sh
```

Build checks use native golden packet vectors, split/malformed/refused reply
fixtures, mocked SPI ioctls, an entirely fake sensor for flow/privacy tests, and
fake temporary filesystem state for runner/archive cleanup tests. None access
hardware or require root. ASan/UBSan can additionally exercise the same C tests.
