# GXFP5120 one-shot key replacement probe

This tool replaces the fingerprint sensor's 32-byte PSK with a new random key.
It is the first **persistent write** in this bring-up. It is not a read-only
probe: if firmware accepts the command, the previous key is gone. The old key
was not recovered, so there is no rollback.

It uses the upload path reconstructed from the stock Goodix `gfspi.dll`
1.1.17.140 and reproduced offline. The wrapper construction is cross-checked
against two public synthetic vectors and the independent Python/Windows model.
The runtime seed is the one embedded in the public gxfp5130 Linux payload code
(`02ff20000000` wrapper format).

## What it does, in order

1. Identify the sensor and require firmware `GF_ITE_EC_20066`.
2. Read the existing 32-byte key hash. Stop if it is refused or unavailable.
3. Generate a 32-byte PSK and an 8-byte host-cache seed from `getrandom`.
4. Build the 102-byte authenticated/encrypted wrapper and its SHA-256.
5. Create `/var/lib/fingerprint-gxfp5120.psk` (32 raw bytes, root-owned and
   mode 0600). Require both the file and `/var/lib` to sync successfully before
   sending the upload. Abort on any storage failure or if the path exists.
6. Send one `E0` production command with the `BB010002` empty host-cache field
   and `BB010003` wrapper, using the stock ITE fragmentation and counters.
7. Wait at most one second for the command ACK and zero-status completion.
8. Read `BB020003` for up to 1.5 seconds and compare with SHA-256(wrapper).

There is no retry at any layer. A missing ACK or completion does not cause a
resend. The probe still performs the bounded hash check, because a write may
have landed even when the reply was lost.

## Outcomes

```text
result=key_replaced_verified                 write ACK + status 0 + hash match (exit 0)
result=key_replaced_completion_unconfirmed   hash match, but ACK/completion missing (exit 2)
result=key_replacement_unverified            clean completion, hash did not match (exit 2)
result=key_write_failed_existing_hash_unchanged  write failed, old digest still present (exit 2)
result=key_write_failed_hash_changed_not_new     write failed, digest changed to a third value (exit 2)
result=key_write_failed_state_unknown        write failed and no hash reply (exit 2)
result=existing_hash_unavailable_stop        stopped before generating or writing (exit 2)
```

Only a verified hash means the sensor stores exactly the wrapper that was
saved. It does **not** prove that the new PSK works for TLS. The MCU-state and
TLS paths were never established on this firmware. A later, separately reviewed
step must test the handshake.

## Payload choice

The normal stock upload always carries a Windows DPAPI-sealed host-cache blob
in `BB010002`. Linux has no DPAPI. This probe uses the same native serializer's
empty-host-cache case: `BB010002` length 8, followed by an 8-byte random seed,
then the 102-byte `BB010003` wrapper. The public gxfp5130 Linux payload builder
also accepts a zero-length sealed field and generates its 8-byte seed randomly.

**Acceptance of the empty host-cache field by 20066 firmware is unverified.**
If firmware requires a nonempty field, it should refuse the command; but this
is not guaranteed. The completion status and hash check are the only feedback.

## Why the seed is safe to assume

The wrapper uses the mode-0 runtime seed. It is the same 32-byte constant in
the stock DLL and in the public Linux `gxfp5130-linux` payload implementation,
and the `02ff20000000` header, IV derivation, AES-256-GCM AAD, HMAC layout and
TLV builder all match. The DLL's mode global is zero-initialized in `.data`, so
mode 0 is the default. This is strong protocol evidence, not proof that this
particular MCU fuses the same seed.

## Transport and privacy

Same strict identity checks and runner as the read-only probes: only
`spi-GXFP5120:00` under PCI `00:1e.3`, mode 0, 8-bit, requested 10 MHz. Never
`spi0.0` (system flash).

The new PSK is never printed or written to the scratch directory or report.
The report contains a summary and the prior digest, not the raw SPI log, wrapper,
or payload. Process dumpability is disabled before key generation. Keep both
key and report private; do not commit or upload them.

The recovery file is on `/var/lib` rather than `/tmp`. The probe checks for the
reviewed filesystem type and directory ownership, but the operator must also
verify that `/var/lib` is still on portatilo's persistent encrypted volume.
The file stays in place even if the probe is interrupted or report export fails.
An existing path intentionally blocks another run, including when a storage
failure left a partial key file. Do not remove it to bypass the retry guard.

## Risks

- The old key cannot be restored.
- Firmware may reject or partially apply the production command.
- A power loss during the write leaves an unknown key state.
- A successful hash does not guarantee TLS usability.
- Enabling fingerprint login still requires a separate PAM/security step.

This is an offline-tested prototype. A live run requires separate explicit
approval, plus `--replace-psk` on the runner command line. The runner temporarily
binds the sensor, then restores the binding/override and saves a private report.
Do not rerun after an uncertain result; inspect the report and hash outcome first.
