{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  writeShellScript,
}:
stdenvNoCC.mkDerivation {
  pname = "google-sans";
  version = "0-unstable-2025-08-26";
  src = fetchFromGitHub {
    owner = "hprobotic";
    repo = "Google-Sans-Font";
    rev = "42c6b3e1bb33c4a9831adb3406c3b7eef47d737b";
    hash = "sha256-y5lMVJzFLhIOtph7JgYD69wH+Vd8f1JE2/Ln3EMKG38=";
  };

  dontBuild = true;
  dontFixup = true;
  dontConfigure = true;

  installPhase = # sh
    ''
      runHook preInstall
      install -Dm644 *.ttf -t "$out/share/fonts/truetype/Google-Sans"
      runHook postInstall
    '';

  passthru.updateScript = import ../lib/make-update-script.nix {
    inherit writeShellScript;
    pkgPath = ./.;
    name = "update-google-sans";
  };

  meta = {
    description = "Google Sans font family";
    homepage = "https://github.com/hprobotic/Google-Sans-Font";
    license = lib.licenses.unfree;
    platforms = lib.platforms.all;
  };
}
