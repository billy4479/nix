{
  stdenvNoCC,
  lib,
  domain,
  bind9-hosts,
  generated-records,
  ...
}:
stdenvNoCC.mkDerivation {
  pname = "bind9-config";
  version = "1.0.0";
  src = ./config;

  dontBuild = true;

  postPatch = # sh
    ''
      substituteInPlace named.conf *.zone --replace-fail '@domain@' ${lib.escapeShellArg domain}
    '';

  installPhase = # sh
    ''
      mkdir -p $out
      cp -r * $out
      cp ${bind9-hosts} $out/blacklist.conf
      cp ${generated-records} $out/generated-records.zone
      mkdir -p $out/examples
    '';
}
