# One-shot fingerprint ACPI resource query

This helper resolves the GPIO resources of `\_SB.PC00.SPI1.FPNT` without binding
a fingerprint driver or communicating with the sensor. It is a diagnostic,
not a fingerprint driver or provisioning tool.

## Run on portatilo

A built bundle is placed at `/home/billy/fingerprint-acpi-resources`. Review
`gxfp_acpi_resources.c` and `run.sh` there, then run:

```sh
sudo ~/fingerprint-acpi-resources/run.sh
```

The runner:

1. Verifies the bundle checksums, exact running kernel store path/release, and
   the SHA-256 of the DSDT already reviewed in the passive inspection.
2. Requires the fingerprint device to be unbound and the helper to be unloaded.
3. Records the existing sensor SPI counters.
4. Loads the module, copies its stored report, and unloads it immediately.
5. Records counters again and saves a private, user-owned
   `~/fingerprint-acpi-report.*.txt` file.

There is no automatic driver binding, module installation, GPIO request,
interrupt registration, SPI transaction, reset pulse, or key/firmware write.
On most failures after loading, the exit trap attempts to unload the helper.
If unloading fails, it prints the manual cleanup command:

```sh
sudo rmmod gxfp_acpi_resources
```

Loading an out-of-tree/unsigned module can set the kernel's O/E taint flags.
Those flags persist until reboot even after unloading. Kernel code and ACPI
execution cannot be made risk-free; the VM tests reduce implementation risk but
do not establish behavior of the real firmware.

## What the code queries

The only requested resource method is the fixed device's `_CRS`. Before that,
the module resolves its fixed namespace handle and checks the hardware ID using
ACPICA object information. It accepts only `GXFP5120` and the expected layout:
one SPI resource, one GPIO interrupt resource, and one GPIO I/O resource, each
GPIO descriptor containing exactly one pin.

The inspected `_CRS` reads firmware GNVS fields and computes a resource buffer.
The runner's DSDT hash guard prevents silently using a different implementation
after a BIOS update. The helper does not evaluate `_INI`, read `FPAD`/the `_DSM`
boot buffer, expose arbitrary ACPI calls, or map physical memory.

After initialization the sysfs report is stored text, not a live query:

```text
/sys/module/gxfp_acpi_resources/parameters/report
```

It is read-only, and supplying `report=` at module load is explicitly rejected.
The code exports no driver aliases, binds to no bus, and has no GPIO/SPI imports.

## Reading the result

The report contains:

- `spi`: controller, chip select, speed, word size, clock and CS flags.
- `gpio-int`: resolved controller-relative pin, triggering and polarity.
  `triggering=1 polarity=0` means edge-triggered, active high.
- `gpio-io`: resolved output/control pin. Its purpose and active level are not
  established by this query. Do not interpret its generic `polarity` field as
  reset polarity; that interpretation applies to interrupt resources.
- `complete=1`: the query and expected-layout checks succeeded.

The pin values in VM logs are deliberately synthetic and are not identification
of portatilo's real GPIOs. Compare the real returned controller/pins with the
passive pin-controller snapshot before requesting any line.

## Build and validate

From the repository root, build against portatilo's configured kernel:

```sh
nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake (toString ./.);
      host = f.nixosConfigurations.portatilo;
  in host.config.boot.kernelPackages.callPackage ./scripts/fingerprint/acpi-resources { }
'
```

This is an ordinary external-module build using the exact kernel headers and
module build flags. It does not build/deploy a new system or install the module.
Nixpkgs provides the general-purpose `acpi-call` module; this intentionally uses
a fixed-path query instead of exposing arbitrary ACPI method execution.

Run the synthetic integration tests with:

```sh
nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake (toString ./.);
      host = f.nixosConfigurations.portatilo;
      helper = host.config.boot.kernelPackages.callPackage ./scripts/fingerprint/acpi-resources { };
  in helper.tests.vm
'
```

The test boots the same kernel in three diskless QEMU/TCG guests, with no host
filesystem, passthrough devices, network adapters, or KVM requirement:

- Synthetic ACPI device: dynamic pin placeholders are replaced correctly,
  metadata and pins are reported, sysfs writes and `report=` input are rejected,
  and the module unloads cleanly.
- No target device: module initialization fails without leaving it loaded.
- Wrong HID at the correct path: the helper refuses to query resources.

These test the kernel module, not the laptop runner's real firmware/kernel
identity checks. The runner is separately syntax-checked and ShellCheck-checked.
The test output contains `good.log`, `absent.log`, and `wrong-hid.log`.
