{
  lib,
  stdenv,
  kernel,
}:
stdenv.mkDerivation {
  pname = "gxfp-version-probe";
  version = "1";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./protocol.c
      ./protocol.h
      ./probe.c
      ./test_protocol.c
    ];
  };

  buildPhase = # sh
    ''
      runHook preBuild
      $CC -std=c11 -O2 -Wall -Wextra -Werror protocol.c probe.c -o version-probe
      runHook postBuild
    '';
  doCheck = true;
  checkPhase = # sh
    ''
      $CC -std=c11 -O2 -Wall -Wextra -Werror protocol.c test_protocol.c -o test-protocol
      ./test-protocol
      ./version-probe --help
    '';
  installPhase = # sh
    ''
      mkdir -p "$out"
      install -m 555 version-probe "$out/"
      printf '%s\n' '${kernel.modDirVersion}' >"$out/kernel-release"
      printf '%s\n' '${kernel.outPath}' >"$out/kernel-path"
    '';

  meta = {
    description = "Fixed firmware-version-only query for portatilo's ITE GXFP5120";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.mit;
  };
}
