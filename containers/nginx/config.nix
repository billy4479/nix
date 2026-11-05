{
  stdenvNoCC,
  lib,

  externalTrafficFrom,
  ...
}:
stdenvNoCC.mkDerivation {
  pname = "nginx-config";
  version = "1.0.0";
  src = ./config;

  dontBuild = true;

  installPhase = # sh
    ''
      mkdir -p $out
      cp -r * $out
    '';

  postPatch = # sh
    ''
      substituteInPlace nginx.conf --replace-fail '@@EXTERNAL_TRAFFIC@@' \
        ${lib.escapeShellArg (
          lib.concatMapStringsSep "\n" (ip: "set_real_ip_from ${ip};") externalTrafficFrom
        )}
    '';
}
