{
  bun,
  fetchFromGitHub,
  lib,
  stdenvNoCC,
  writableTmpDirAsHomeHook,
}:

rec {
  version = "2.6.0";

  src = fetchFromGitHub {
    owner = "openchamber";
    repo = "openchamber";
    tag = "v${version}";
    hash = "sha256-sIAd+OpL2y/Zrx/3Xaoqb0kztaqTPu3zlP4g99ieP5o=";
  };

  mkBunModules =
    {
      pname,
      hash,
      installFlags ? [ ],
    }:
    stdenvNoCC.mkDerivation {
      pname = "${pname}-node-modules";
      inherit version src;

      impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
        "GIT_PROXY_COMMAND"
        "SOCKS_SERVER"
      ];

      nativeBuildInputs = [
        bun
        writableTmpDirAsHomeHook
      ];

      env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

      dontConfigure = true;
      dontFixup = true;

      buildPhase = # sh
        ''
          runHook preBuild

          export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
          bun install ${lib.escapeShellArgs installFlags}

          runHook postBuild
        '';

      installPhase = # sh
        ''
          runHook preInstall

          mkdir -p $out
          cp -R node_modules $out/node_modules

          runHook postInstall
        '';

      outputHashMode = "recursive";
      outputHash = hash;
    };

  configureNodeModules =
    { nodeModules }:
    # sh
    ''
      cp -R ${nodeModules}/node_modules .
      chmod -R u+w node_modules
      patchShebangs node_modules
      node fix-deprecation.js
    '';

  installKatexFonts = # sh
    ''
      katexFonts=node_modules/katex/dist/fonts
      if ! test -d "$katexFonts"; then
        katexFonts=packages/ui/node_modules/katex/dist/fonts
      fi
      mkdir -p packages/web/dist/assets/fonts
      cp -R "$katexFonts"/. packages/web/dist/assets/fonts
    '';
}
