{
  lib,
  stdenv,
  buildPackages,
  kernel,
}:
stdenv.mkDerivation {
  pname = "gxfp-readback-probe";
  version = "2";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ./.
      ../spi
      ../version-probe/run.sh
    ];
  };
  nativeCheckInputs = [
    buildPackages.python3
    buildPackages.shellcheck
  ];
  dontPatchShebangs = true;
  buildPhase = # sh
    ''
      runHook preBuild
      $CC -std=c11 -O2 -Wall -Wextra -Werror readback-probe/protocol.c readback-probe/probe.c spi/queries.c spi/transport.c -o readback-probe-bin
      runHook postBuild
    '';
  doCheck = true;
  checkPhase = # sh
    ''
      runHook preCheck
      $CC -std=c11 -O2 -Wall -Wextra -Werror readback-probe/protocol.c readback-probe/test_protocol.c spi/queries.c -o test-protocol
      ./test-protocol
      $CC -std=c11 -O2 -Wall -Wextra -Werror spi/transport.c spi/queries.c spi/test_transport.c -Wl,--wrap=ioctl -o test-transport
      ./test-transport
      $CC -std=c11 -O2 -Wall -Wextra -Werror readback-probe/protocol.c readback-probe/probe.c readback-probe/mock_transport.c spi/queries.c -o test-probe
      python readback-probe/test_probe.py ./test-probe
      python readback-probe/test_runner.py version-probe/run.sh
      bash -n version-probe/run.sh
      shellcheck version-probe/run.sh
      ./readback-probe-bin --help
      runHook postCheck
    '';
  installPhase = # sh
    ''
      runHook preInstall
      mkdir -p "$out/source/spi" "$out/source/readback-probe" "$out/source/version-probe"
      install -m 555 readback-probe-bin "$out/readback-probe"
      install -m 555 version-probe/run.sh "$out/run.sh"
      cp readback-probe/README.md "$out/README.md"
      cp version-probe/run.sh "$out/source/version-probe/"
      cp spi/* "$out/source/spi/"
      cp readback-probe/* "$out/source/readback-probe/"
      printf '%s\n' readback >"$out/probe-kind"
      printf '%s\n' '${kernel.modDirVersion}' >"$out/kernel-release"
      printf '%s\n' '${kernel.outPath}' >"$out/kernel-path"
      runHook postInstall
    '';
  # The binary must be stripped before its digest is recorded.
  postFixup = # sh
    ''
      cd "$out"
      find . -type f ! -name SHA256SUMS -printf '%P\0' | LC_ALL=C sort -z | xargs -0 sha256sum >SHA256SUMS
      sha256sum --check --status SHA256SUMS
    '';
  meta = {
    description = "Fixed private existing-key readback probe for portatilo's GXFP5120";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.mit;
  };
}
