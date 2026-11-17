# Portatilo fingerprint reader: offline investigation

## Conclusion

**Windows is not intrinsically required to generate the key material.** The
GXFP5120 Windows driver generates a random 32-byte key and provisions it into the
sensor. Its sensor-side key wrapper has been reproduced on Linux and compared
byte for byte with the original Windows machine code.

**This does not mean portatilo's reader is working yet.** No sensor commands,
provisioning writes, firmware updates, authentication changes, or deployments were
performed during this investigation. Acceptance of a new key by this particular
sensor remains untested. No actual device key was obtained or generated.

The next useful experiment is hardware identification and readback, not a blind
key upload. Keep password authentication throughout bring-up.

**Follow-up:** [the official upload path](FINGERPRINT-UPLOAD.md) has since been
traced through original-driver emulation down to individual SPI buffers, with
mocked acknowledgements, completion replies, and hash readback. This adds a
verified host-side packet specification, not evidence of real MCU acceptance.

## Hardware actually observed

Read-only inspection over SSH found:

- Manufacturer/model: HUAWEI `BOD-WXX9`, product version `M1060`.
- ACPI ID: `GXFP5120`.
- Sensor sysfs device: `spi-GXFP5120:00`.
- Parent: PCI `0000:00:1e.3`, `pxa2xx-spi.2`, `spi_master/spi1`.
- No bound driver for the sensor at inspection time.
- A **different** device, `spi0.0`, is bound to `spi-nor` at PCI `0000:00:1f.5`.

Do not target `spi0.0`: it is not the fingerprint reader. The community driver's
hardcoded `/dev/spidev0.0` default must not be copied onto this laptop. Discover
the sensor's actual spidev node after binding only its ACPI device.

The matching community project was developed on a MateBook D 14. That is the
reference laptop, not an identification of portatilo. Matching ACPI ID and
controller location are encouraging but do not establish the MCU firmware,
GPIO mapping, sensor die, or calibration parameters of this unit.

## What the small Windows package contains

[Microsoft Update Catalog entry](https://www.catalog.update.microsoft.com/Search.aspx?q=GXFP5120)
provides Goodix FP 1.1.17.140. The inspected package was update
`a4725f20-1cfc-47de-94a5-7795aa43df6f`:

[Direct CAB download](https://catalog.s.download.windowsupdate.com/c/msdownload/update/driver/drvs/2021/07/77a2bcbf-fb01-4697-833e-9f49272a3bd6_dec86db41e5203223b9553d2e809f71de19e9658.cab)

The CAB is 877,780 bytes; its files total 3,634,422 bytes unpacked. It contains:

- `gfspi.inf`, `gfspi.cat`, `gfspi.dll`: device installation and the UMDF driver.
  The INF explicitly lists `ACPI\GXFP5120 ; ITE EC` and version 1.1.17.140.
- `EngineAdapter.dll`: Windows Biometric Framework integration.
- `AlgoMilan.dll`, `AlgoChicago.dll`: fingerprint algorithms.
- `GoodixEventLog.dll`, `SessionService.exe`: supporting logging and service code.

Windows supplies the remaining OS infrastructure, which helps explain the small
package. The downloaded binaries were inspected and emulated, not installed.

SHA-256 identifiers:

```text
CAB
216f7973b0c78c2aff506bcffbebedbd284ea0d3571d84751ec10b6a640b6685
gfspi.dll
074c7425704bc61cab63ab61ff9c50dcae6eb0dd896c87b0e2f0c862e585aa34
EngineAdapter.dll
965c0b37735add6e06c2425b138ab178f7da195b7fdde6e42d63b9873d9293ae
```

## How initialization and key storage work

The relevant logic is in `gfspi.dll`, not just the Windows Hello adapter:

1. Try to obtain an existing host key from `Goodix_Cache.bin`.
2. If necessary, read the sensor's `BB010002` data and try unsealing its
   Windows-protected copy.
3. Reconstruct the sensor wrapper from the recovered key, hash it, and compare
   against the sensor's `BB020003` value.
4. If validation repeatedly fails, enter `production_write_key`:
   - Generate a fresh 32-byte PSK using Windows cryptographic randomness.
   - Generate an 8-byte seed and derive entropy for DPAPI sealing.
   - Protect the host copy with `CryptProtectData`, using flag `4`,
     `CRYPTPROTECT_LOCAL_MACHINE`.
   - Separately wrap the same PSK for the sensor.
   - Upload the combined TLV structure to the MCU.
   - Save the sealed host copy plus seed to `Goodix_Cache.bin`.
5. Check the key again before continuing.

These are two distinct protection layers:

- **Host cache:** Windows DPAPI. A cache copied from another Windows installation
  is not automatically usable. The driver can replace a mismatched key.
- **Sensor wrapper:** deterministic AES-GCM/HMAC construction using constants
  reconstructed from the driver. It does not require Windows DPAPI to compute.

The driver's combined upload, in little-endian TLV form, is:

```text
BB010002 | length | DPAPI-sealed PSK | seed8
BB010003 | length | sensor wrapper
zero padding to a four-byte boundary
```

A Linux-only host could instead keep the raw PSK in a root-only state file. The
remaining hardware question is whether this MCU accepts a provision containing
an empty/non-Windows host-cache field, as supported by sibling Linux code, or
requires a different representation. That was not established offline.

Creating a random `psk.bin` alone will NOT work: the reader must hold the same
key. Creating a valid wrapper alone also does not demonstrate that a device
will accept it. A future Windows boot may replace a Linux-provisioned key;
Linux would then need to recover or reprovision the matching key again.

## Sensor wrapper: independently verified

For a 32-byte PSK, the wrapper is 102 bytes:

```text
HMAC-SHA256[32] | header[6] | IV[16] | ciphertext[32] | GCM tag[16]
```

- Header: `02 ff 20 00 00 00`.
- IV: first 16 bytes of SHA-256 over the header, first eight PSK bytes, and
  sixteen repetitions of little-endian integer `3`.
- A fixed, obfuscated runtime seed feeds an HMAC-SHA256 counter derivation.
  Two seed-generation branches exist; both were emulated and tested.
- Encryption: AES-256-GCM with fixed associated data.
- Outer HMAC covers the header, ciphertext, and tag, but not the IV. GCM
  authentication still detects an altered IV.

The exact derivation and constants are in
[`scripts/fingerprint/verify.py`](../scripts/fingerprint/verify.py).
Those constants are not portatilo's device key. All test PSKs are synthetic.

The offline test executes only the seed/wrapping routines of the SHA-256-pinned
DLL under Unicorn, with local allocator/free/cookie hooks. It compares their
outputs against an independent Python implementation using `cryptography`.
It does not boot Windows or execute driver initialization or device I/O.

Results:

- Four synthetic keys across both branches: **8 exact byte-for-byte matches**.
- Authenticated decryption recovered all eight original test keys.
- **40 modified-wrapper cases rejected**, covering HMAC, header, IV,
  ciphertext, and tag changes.

This proves wrapping compatibility with the inspected DLL, not live sensor
compatibility, a complete protocol implementation, or general biometric security.

### Reproduce the offline checks

Extract `gfspi.dll` from the linked CAB, then run from this repository:

```sh
nix shell --impure --expr '
  let p = (builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux;
  in p.python3.withPackages (ps: [ps.pefile ps.unicorn ps.cryptography])
' -c python scripts/fingerprint/verify.py /path/to/gfspi.dll
```

The harness rejects any DLL with a different hash. It writes no key files and
has no sensor transport code. Do not use its public test keys on a real reader.

## Relevant reverse-engineering landmarks

Addresses below are RVAs in the inspected `gfspi.dll`, image base `0x180000000`.
Function names were recovered from logging strings and cross-references;
decompiler output alone was not treated as proof of cryptographic equivalence.

| RVA | Role |
| --- | --- |
| `0x0407d0` | `production_psk_process`: validate, then generate/upload on failure |
| `0x03f99c` | `production_check_psk_is_valid` |
| `0x03fef0` | `production_get_host_psk_data`: cache/readback/unseal/re-wrap |
| `0x041460` | `production_write_key` |
| `0x006c60` | Construct sensor wrapper, verified by emulation |
| `0x006640`, `0x006950` | Normal runtime seed generation |
| `0x005f30`, `0x0062c0` | Alternate seed-generation branch |
| `0x005bd0` | HMAC counter key derivation |
| `0x007380` | `SecSha256`, used to hash the reconstructed wrapper |
| `0x041118` | Read specific production data by type |
| `0x040c7c` | MCU production read, command group `0x0e`, subcommand `2` |
| `0x041d68` | MCU production write, command group `0x0e`, subcommand `0` |
| `0x00bc34`, `0x00bf40` | DPAPI protect/unprotect helpers |

The protocol's corresponding command bytes are `0xe4` for read and `0xe0` for
write. This is a map for further development, not an instruction to transmit
those commands blindly.

## Existing Linux work and its limits

### GXFP5120 driver

[strenica/gxfp5120-linux](https://github.com/strenica/gxfp5120-linux/tree/629bad01c7427e1bf2970de5813e50aa4fdde0b5)
reports successful enrollment, verification, fprintd, and PAM on its reference
laptop. Its stack is:

```text
SPI + GPIO events -> ITE parcels -> Goodix messages -> TLS-PSK
  -> fingerprint frames -> image processing -> host-side matcher
  -> libfprint -> fprintd -> optional PAM integration
```

The reference uses 10 MHz SPI mode 0 and a GPIO interrupt per response parcel.
GPIO chip/line and configuration must be verified for portatilo, not assumed.
The driver reads a 32-byte PSK file; it does not implement initial provisioning.
Its README therefore documents Windows extraction as the supported setup route.

Once authenticated, it decodes 80x64, 12-bit captures, processes them and uses a
host-side FAST/BRIEF/RANSAC matcher with a raster correlation gate. This is not
an on-sensor Windows Hello matching implementation.

**Security caveat:** the inspected `gx_tls_decrypt_app` decrypts CBC image records
without validating their record MAC. Its random-byte helper also falls back to
time-derived values if `/dev/urandom` fails. These are concrete reasons to keep
the experimental driver out of PAM initially. Working scan/enrollment reports
are not a quantified false-accept-rate study or a security audit.

### Sibling provisioning code

[Metrohan/gxfp5130-linux](https://github.com/Metrohan/gxfp5130-linux/tree/5e8c91c6b63da472dad946fbfdad2f43bca21eb4)
has a Linux-only provisioning tool and a matching normal-branch wrapper format.
Its `userspace/src/algo/payload/provision.c` supplied a useful comparison, but it
is **not a drop-in solution**: GXFP5130 uses a different eSPI mailbox transport.
Also, its `gxfp_payload_build_bb020003_hash_prefix` uses a SHA-384 prefix, whereas
this GXFP5120 DLL calls `SecSha256` on its wrapper. Copying that hash check
unchanged would be wrong for the inspected Windows implementation.

[goodix-fp-dump](https://github.com/goodix-fp-linux-dev/goodix-fp-dump/tree/cc43bb3b3154a0bccc0412ae024013c7e1923139)
provides additional command-format references. Some family scripts write fixed
public keys or firmware. They must not be run as harmless detection tools.
GXFP51A0 examples use yet another MCU/firmware path and are not evidence that
portatilo has the same firmware or key length.

## What remains and a safe order of work

1. **Identify without provisioning.** Decode the laptop's ACPI resources to
   establish GPIO/polarity; bind only the sensor to spidev; request its firmware
   version and status with an explicit no-persistent-write command allowlist.
   Even these live protocol exchanges are a separate step from this offline
   investigation and require privileged device access.
2. **Try readback first.** Read the existing provisioning data, if permitted by
   this firmware, and preserve it privately. If `BB010003` is readable and uses
   the verified wrapper, authenticated offline recovery may avoid DPAPI and any
   provisioning write. Neither read access nor a pre-existing key is established.
3. **Provision only if needed.** Adapt the proven wrapper to the ITE transport,
   use a unique cryptographically random key, back up readable state, validate
   replies, then prove a TLS session. Do not flash firmware or use `/dev/mem`.
   Persistence, retry behavior, recovery after interrupted writes, and Windows
   interoperability still need explicit testing.
4. **Capture before authentication.** Obtain a frame and validate calibration,
   finger-present behavior, repeated captures, reboot, and suspend/resume.
5. **Package for NixOS.** Patch libfprint, bind by ACPI identity, allow only the
   actual SPI/GPIO nodes in fprintd, and keep keys in private runtime state, never
   Git or the world-readable Nix store. Deployment remains the user's task.
6. **Harden and evaluate before PAM.** Fix transport authentication checks,
   confirm fail-closed error handling, and measure genuine/other-finger behavior.
   Keep password fallback and treat biometric templates as sensitive data.

**Practical assessment:** the cryptographic construction is no longer a blocker.
Transport and device-specific acceptance remain the bring-up risk. Reliable,
security-reviewed fingerprint login is a later milestone, not something this
offline result establishes.
