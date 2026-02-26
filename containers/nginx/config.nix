{
  stdenvNoCC,
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
}
