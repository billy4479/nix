# Portatilo: private existing-key readback (v2)

Prepared for a separate manual sudo run. No live queries are run during build or
delivery. This is not an authentication driver, initialization script or key
provisioner.

## Fixed command allowlist

In order, without command retries:

1. `A8`, two zero bytes: require a successful A8 ACK followed by exactly
   `GF_ITE_EC_20066`. Ignore a version frame received before the ACK, because the
   mailbox can still contain a cached reply. Stop on a different/unavailable
   version or missing ACK.
2. `E4`, `BB020003:LE32 00000000`: read existing key-wrapper hash. Require status
   zero, exact declared length and 32 data bytes. Accept either the echoed
   `BB020003` selector or the observed `BB010003` stored-object tag. The OEM
   reader accepts the latter too. Stop on refusal, timeout, malformed data or
   an unexpected size, without attempting wrapped-key readback.
3. `E4`, `BB010003:LE32 00000000`: read the existing wrapped key. Save a
   checksum-valid, correctly tagged response privately. Ignore a replayed
   32-byte hash, rather than letting it complete this request. Expect the
   previously analyzed 102-byte format with header `02ff20000000` at offset 32;
   preserve other unexpected formats privately but report exit 2, not success.

The first user-run v1 probe did receive a checksum-valid 32-byte hash response,
but incorrectly reported `hash_unavailable` because it required an echoed hash
selector. Its capture also contained a cached version followed later by the A8
ACK and new version reply. Corrected decoding was verified against that private
capture offline. Only synthetic digest data is used in committed regressions.

MCU-state probing is paused: v1 captured no `AE` reply. V2 sends no `AF`/state
request and does not try alternate state checksums, initialization or resets.

`BB010002` (Windows host backup) is not requested. There is no arbitrary command,
tag, payload, offset or length CLI, and no `E0` provisioning command, reset,
configuration, TLS, GPIO request, image acquisition, enrollment, key generation
or fallback path. These reads necessarily affect volatile EC/SPI state; they
are not a claim that the whole device remains electrically untouched.

The wrapped-key read, canonical-tag hash response and `bb f1 00 00` write/read
operation were checked against original `gfspi.dll` machine code with simulated
Windows APIs and SPI. The state request remains verified offline but is not used
by v2. Live hash readback is now confirmed, not wrapped-key permission or any
provisioning/persistence policy.

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
raw SPI log and any collected `key-hash.bin` and `wrapped-key.bin`.
Terminal output contains only fixed firmware/profile text and result/status
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
sudo ~/fingerprint-readback-probe-v2/run.sh
```

Do not retry the original v1 bundle. Install v2 separately at the path above.

Build checks use native golden packet vectors, canonical/echoed reply tags,
cached-version ACK ordering, stale-hash rejection, split/malformed/refused
fixtures, mocked SPI ioctls, a fake sensor for flow/privacy tests, and fake
temporary filesystem state for runner/archive cleanup tests. None access
hardware or require root. ASan/UBSan can additionally exercise the same C tests.
