{
  lib,
  stdenv,
  buildPackages,
  kernel,
  mbedtls,
}:
stdenv.mkDerivation {
  pname = "gxfp-provision-probe";
  version = "3";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ./.
      ../spi
      ../readback-probe/protocol.c
      ../readback-probe/protocol.h
      ../readback-probe/test_runner.py
      ../version-probe/run.sh
    ];
  };
  nativeCheckInputs = [
    buildPackages.python3
    buildPackages.shellcheck
  ];
  dontPatchShebangs = true;
  NIX_CFLAGS_COMPILE = "-I${mbedtls}/include";
  NIX_LDFLAGS = "-L${mbedtls}/lib";
  buildPhase = # sh
    ''
      runHook preBuild
      $CC -std=c11 -O2 -Wall -Wextra -Werror \
        provision-probe/provision.c provision-probe/wrap.c provision-probe/payload.c \
        readback-probe/protocol.c spi/queries.c spi/transport.c \
        -lmbedcrypto -o provision-probe-bin
      runHook postBuild
    '';
  doCheck = true;
  checkPhase = # sh
    ''
      runHook preCheck
      $CC -std=c11 -O2 -Wall -Wextra -Werror \
        provision-probe/wrap.c provision-probe/test_wrap.c -lmbedcrypto -o test-wrap
      ./test-wrap
      $CC -std=c11 -O2 -Wall -Wextra -Werror \
        provision-probe/payload.c provision-probe/test_payload.c -o test-payload
      ./test-payload
      $CC -std=c11 -O2 -Wall -Wextra -Werror \
        provision-probe/provision.c provision-probe/wrap.c provision-probe/payload.c \
        provision-probe/mock_transport.c readback-probe/protocol.c spi/queries.c \
        -DRECOVERY_DIR='"recovery"' -Wl,--wrap=fstatfs,--wrap=write,--wrap=fsync \
        -lmbedcrypto -o test-provision
      python provision-probe/test_provision.py ./test-provision
      $CC -std=c11 -O2 -Wall -Wextra -Werror \
        spi/transport.c spi/queries.c spi/test_transport.c -Wl,--wrap=ioctl -o test-transport
      ./test-transport
      python readback-probe/test_runner.py version-probe/run.sh
      bash -n version-probe/run.sh
      shellcheck version-probe/run.sh
      ./provision-probe-bin --help
      runHook postCheck
    '';
  installPhase = # sh
    ''
      runHook preInstall
      mkdir -p "$out/source/spi" "$out/source/provision-probe" "$out/source/readback-probe" "$out/source/version-probe"
      install -m 555 provision-probe-bin "$out/provision-probe"
      install -m 555 version-probe/run.sh "$out/run.sh"
      cp provision-probe/README.md "$out/README.md"
      cp version-probe/run.sh "$out/source/version-probe/"
      cp spi/* "$out/source/spi/"
      cp readback-probe/protocol.c readback-probe/protocol.h "$out/source/readback-probe/"
      cp provision-probe/* "$out/source/provision-probe/"
      printf '%s\n' provision >"$out/probe-kind"
      printf '%s\n' '${kernel.modDirVersion}' >"$out/kernel-release"
      printf '%s\n' '${kernel.outPath}' >"$out/kernel-path"
      runHook postInstall
    '';
  postFixup = # sh
    ''
      cd "$out"
      find . -type f ! -name SHA256SUMS -printf '%P\0' | LC_ALL=C sort -z | xargs -0 sha256sum >SHA256SUMS
      sha256sum --check --status SHA256SUMS
    '';
  meta = {
    description = "Experimental one-shot PSK replacement probe for portatilo's GXFP5120";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.mit;
  };
}
