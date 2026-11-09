{
  bun,
  callPackage,
  lib,
  makeWrapper,
  node-gyp,
  nodejs,
  nodejs-slim,
  opencode,
  python3,
  stdenv,
  writableTmpDirAsHomeHook,
  writeShellScript,
}:

let
  common = callPackage ./common.nix { };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "openchamber-web";
  inherit (common) version src;

  buildNodeModules = common.mkBunModules {
    pname = "${finalAttrs.pname}-build";
    installFlags = [
      "--filter"
      "openchamber-monorepo"
      "--filter"
      "@openchamber/ui"
      "--filter"
      "@openchamber/web"
      "--frozen-lockfile"
      "--ignore-scripts"
      "--linker=hoisted"
      "--no-progress"
    ];
    hash = "sha256-KCHqOb2u5edEqny/LA4A5nTA/G7JtFV3iUcZ00KvDf4=";
  };

  runtimeNodeModules = common.mkBunModules {
    pname = "${finalAttrs.pname}-runtime";
    installFlags = [
      "--filter"
      "@openchamber/web"
      "--frozen-lockfile"
      "--ignore-scripts"
      "--linker=hoisted"
      "--no-progress"
      "--production"
    ];
    hash = "sha256-X25ich9niC+OEmu3A7xxhti+Ig6Y6gC4Td6A4OoS2IE=";
  };

  nativeBuildInputs = [
    bun
    makeWrapper
    node-gyp
    nodejs
    python3
    writableTmpDirAsHomeHook
  ];

  configurePhase = # sh
    ''
      runHook preConfigure

      ${common.configureNodeModules { nodeModules = finalAttrs.buildNodeModules; }}

      runHook postConfigure
    '';

  buildPhase = # sh
    ''
      runHook preBuild

      bun run --cwd packages/web build
      ${common.installKatexFonts}

      node_modules/.bin/tsc -p packages/sdk/tsconfig.build.json

      rm -rf node_modules
      cp -R ${finalAttrs.runtimeNodeModules}/node_modules .
      chmod -R u+w node_modules
      rm -f node_modules/.bin/openchamber node_modules/@openchamber/web
      PATH="${lib.makeBinPath [ nodejs-slim ]}:$PATH" patchShebangs node_modules
      node fix-deprecation.js

      nodeGyp=(
        ${lib.getExe nodejs}
        ${node-gyp}/lib/node_modules/node-gyp/bin/node-gyp.js
      )
      nodeGypFlags=(
        --nodedir=${nodejs}
        --build-from-source
        --jobs="''${NIX_BUILD_CORES:-1}"
      )
      ptyDir=node_modules/node-pty
      rm -rf "$ptyDir/prebuilds"
      "''${nodeGyp[@]}" rebuild --directory="$ptyDir" "''${nodeGypFlags[@]}"
      # Keep the native addon, not node-gyp's build tree and toolchain references.
      cp "$ptyDir/build/Release/pty.node" "$TMPDIR/pty.node"
      rm -rf "$ptyDir/build"
      mkdir -p "$ptyDir/build/Release"
      mv "$TMPDIR/pty.node" "$ptyDir/build/Release/"
      find node_modules -type f -name '*.mk' -delete

      runHook postBuild
    '';

  installPhase = # sh
    ''
      runHook preInstall

      mkdir -p $out/lib/openchamber-web $out/bin
      cp -R node_modules $out/lib/openchamber-web/node_modules
      cp -R packages/web/{bin,dist,public,server,package.json,README.md} $out/lib/openchamber-web
      mkdir -p $out/lib/openchamber-web/packages/sdk
      cp -R packages/sdk/{package.json,dist} $out/lib/openchamber-web/packages/sdk/
      rm -f $out/lib/openchamber-web/node_modules/.bin/openchamber-guest-bundle

      makeWrapper ${lib.getExe nodejs-slim} $out/bin/openchamber \
        --add-flags $out/lib/openchamber-web/bin/cli.js \
        --prefix PATH : ${lib.makeBinPath [ opencode ]}

      runHook postInstall
    '';

  dontPatchELF = true;
  noAuditTmpdir = true;

  disallowedReferences = [
    bun
    nodejs
    node-gyp
    python3
  ];

  passthru = {
    inherit (finalAttrs) buildNodeModules runtimeNodeModules;
    tests.pty = callPackage ./test.nix { openchamber-web = finalAttrs.finalPackage; };
    updateScript = import ../lib/make-update-script.nix {
      inherit writeShellScript;
      pkgPath = ./.;
      name = "update-openchamber-web";
    };
  };

  meta = {
    description = "Web server and CLI for OpenChamber";
    homepage = "https://github.com/openchamber/openchamber";
    changelog = "https://github.com/openchamber/openchamber/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "openchamber";
    platforms = [ "x86_64-linux" ];
  };
})
