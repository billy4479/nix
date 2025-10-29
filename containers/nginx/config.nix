{
  stdenvNoCC,

  cloudflaredAddress,
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
      find . -type f -exec \
        sed -i 's/@@CLOUDFLARED_ADDRESS@@/${cloudflaredAddress}/g' {} \;
    '';
}
