{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
  callPackage,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "gxfp-acpi-resources";
  version = "1-${kernel.modDirVersion}";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Makefile
      ./gxfp_acpi_resources.c
    ];
  };

  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];

  makeFlags = kernelModuleMakeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "M=$(PWD)"
  ];
  buildFlags = [ "modules" ];

  installPhase = # sh
    ''
      runHook preInstall
      mkdir -p "$out"
      install -m 444 gxfp_acpi_resources.ko "$out/"
      printf '%s\n' '${kernel.modDirVersion}' >"$out/kernel-release"
      printf '%s\n' '${kernel.outPath}' >"$out/kernel-path"
      runHook postInstall
    '';

  passthru.tests.vm = callPackage ./tests {
    inherit kernel;
    helper = finalAttrs.finalPackage;
  };

  # Keep the reviewed ELF intact and make no attempt to install/load the module.
  dontStrip = true;
  dontPatchELF = true;
  meta = {
    description = "One-shot read-only ACPI resource query for portatilo's GXFP5120";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.gpl2Only;
  };
})
