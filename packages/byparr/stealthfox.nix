{
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  fetchurl,
  fontconfig,
  freetype,
  glib,
  gtk3,
  lib,
  libGL,
  libdrm,
  libx11,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxscrnsaver,
  libxshmfence,
  libxtst,
  libxcb,
  nspr,
  nss,
  pango,
  patchelf,
  pythonEnv,
  stdenv,
  stdenvNoCC,
  udev,
  zlib,
}:

let
  # The patched Firefox build sealed inside the invisible-core that the
  # source ships. URL, hash and ini facts all come from
  # invisible_core/seal.json; the build asserts the archive against the seal
  # so a stale pin fails loudly, and byparr/update.sh rewrites this pin from
  # the seal on every run.
  engineArchive = fetchurl {
    url = "https://github.com/feder-cr/firefox_antidetect_patch/releases/download/firefox-20/firefox-151.0-stealth-linux-x86_64.tar.gz";
    hash = "sha256-1WWIgMv41sNPjXEEOhiscujKWilpKOtffvnjKkZR2IQ=";
  };

  runtimeLibraryPath = lib.makeLibraryPath [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    glib
    gtk3
    libGL
    libdrm
    libx11
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxscrnsaver
    libxshmfence
    libxtst
    libxcb
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    udev
    zlib
  ];
in
stdenvNoCC.mkDerivation {
  pname = "stealthfox";
  version = "151.0";

  src = engineArchive;

  nativeBuildInputs = [
    patchelf
    pythonEnv
  ];

  dontUnpack = true;

  # invisible-playwright never downloads at runtime as long as this tree is
  # present in its cache root with a matching stamp, so the store path doubles
  # as INVISIBLE_PLAYWRIGHT_CACHE_DIR. The "engine" symlink gives wrappers a
  # stable path to the versioned directory.
  installPhase = # sh
    ''
          runHook preInstall

          facts=$(${pythonEnv}/bin/python -c '
      import json, platform, sys
      from invisible_core.seal import active_seal
      seal = active_seal()
      asset = seal.asset_for(sys.platform, platform.machine())
      print(json.dumps({
          "dir": f"{seal.tag}_{seal.upstream_version}_{asset.build_id}",
          "digest": seal.digest,
          "asset_name": asset.name,
          "asset_sha256": asset.sha256,
          "entry_rel": asset.entry_rel,
      }))
      ')
          fact() { printf '%s' "$facts" | ${pythonEnv}/bin/python -c "import json, sys; print(json.load(sys.stdin)['$1'])"; }

          printf '%s  %s\n' "$(fact asset_sha256)" "$src" | sha256sum -c -

          engineDir="$out/$(fact dir)"
          mkdir -p "$engineDir"
          tar -xf "$src" -C "$engineDir"

          STEALTHFOX_ENGINE_DIR="$engineDir" ${pythonEnv}/bin/python -c '
      import os, platform, sys
      from pathlib import Path
      from invisible_core.seal import active_seal, write_stamp
      seal = active_seal()
      asset = seal.asset_for(sys.platform, platform.machine())
      engine_dir = Path(os.environ["STEALTHFOX_ENGINE_DIR"])
      write_stamp(engine_dir, seal, asset=asset.name, asset_sha256=asset.sha256, adopted=False)
      assert (engine_dir / asset.entry_rel).exists(), "engine entry missing after extraction"
      '

          entry="$engineDir/$(fact entry_rel)"
          chmod u+w "$entry"
          patchelf --set-interpreter "${stdenv.cc.bintools.dynamicLinker}" \
            --set-rpath "${runtimeLibraryPath}:\$ORIGIN" "$entry"

          ln -s "$(fact dir)" "$out/engine"

          # Per-session font manifests are written to <cache root>/fonts; the store
          # is read-only, so that one path lives in the runtime cache instead. It is
          # distinct from the engine's own bundled fonts beside the binary, which
          # stay in the store and are what the manifest is checked against.
          ln -s /tmp/byparr-cache/invisible-playwright-fonts "$out/fonts"

          runHook postInstall
    '';

  passthru = {
    inherit runtimeLibraryPath;
  };

  meta = {
    description = "Patched Firefox engine used by invisible-playwright, laid out as its engine cache";
    platforms = [ "x86_64-linux" ];
  };
}
