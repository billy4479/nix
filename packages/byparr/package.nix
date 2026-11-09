{
  callPackage,
  geoip,
  lib,
  makeWrapper,
  pythonEnv,
  source,
  stdenvNoCC,
  stealthfox,
  version,
  writeShellScript,
  xorg-server,
}:

stdenvNoCC.mkDerivation {
  pname = "byparr";
  inherit version;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = # sh
    ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/app"
      cp "${source.sourcePath}/main.py" "$out/app/"
      cp -R "${source.sourcePath}/src" "$out/app/"
      install -Dm644 "${source.sourcePath}/LICENSE" "$out/share/licenses/byparr/LICENSE"

      makeWrapper "${pythonEnv}/bin/python" "$out/bin/byparr" \
        --chdir "$out/app" \
        --set-default VERSION "${version}" \
        --set INVISIBLE_PLAYWRIGHT_CACHE_DIR "${stealthfox}" \
        --set STEALTHFOX_GEOIP_MMDB "${geoip}" \
        --set-default HOME /tmp/byparr-home \
        --set-default XDG_CACHE_HOME /tmp/byparr-cache \
        --run "mkdir -p /tmp/byparr-cache/invisible-playwright-fonts" \
        --set PYTHONUNBUFFERED 1 \
        --set PYTHONDONTWRITEBYTECODE 1 \
        --prefix PATH : "${lib.makeBinPath [ xorg-server ]}" \
        --prefix LD_LIBRARY_PATH : "${stealthfox}/engine:${stealthfox.runtimeLibraryPath}" \
        --add-flags main.py

      runHook postInstall
    '';

  passthru = {
    tests.driver = callPackage ./test.nix { inherit pythonEnv; };
    updateScript = import ../lib/make-update-script.nix {
      inherit writeShellScript;
      pkgPath = ./.;
      name = "update-byparr";
    };
  };

  meta = {
    description = "FlareSolverr-compatible API using a stealth browser";
    homepage = "https://github.com/ThePhaseless/Byparr";
    license = lib.licenses.gpl3Only;
    mainProgram = "byparr";
    platforms = [ "x86_64-linux" ];
  };
}
