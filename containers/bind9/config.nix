{
  stdenvNoCC,
  bind9-hosts,
  ...
}:
stdenvNoCC.mkDerivation {
  pname = "bind9-config";
  version = "1.0.0";
  src = ./config;

  dontBuild = true;

  installPhase = # sh
    ''
      mkdir -p $out
      cp -r * $out
      cp ${bind9-hosts} $out/blacklist.conf
      mkdir -p $out/examples
    '';
}
