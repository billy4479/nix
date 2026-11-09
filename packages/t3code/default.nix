{
  lib,
  callPackage,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_12,
  pnpmConfigHook,
  nodejs_26,
  nodejs-slim_26,
  node-gyp,
  python3,
  spdx-license-list-data,
  makeWrapper,
  autoPatchelfHook,
  gitMinimal,
  gh,
  writeShellScript,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "t3code";
  version = "0.1.7";

  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    tag = "v${finalAttrs.version}";
    hash = "sha256-oQLmDCDuJPNBsf8MHMD2xhMq+CF6L836/PQesM91Clw=";
  };

  # Restore persisted Pi sessions before rollback on a fresh runtime.
  # https://github.com/pingdotgg/t3code/pull/26322
  # PR head: 2761b809716a1030eca1654e8180db0ad19a728d
  patches = [ ./pi-rollback.patch ];

  pnpmWorkspaces = [
    "@t3tools/monorepo"
    "t3..."
    "@t3tools/scripts..."
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      pnpmWorkspaces
      ;
    pnpm = pnpm_12;
    fetcherVersion = 5;
    hash = "sha256-d3o4kSc4K/YkMuSwGJrAnoSRK7k9iFGdGwyVE9c1aYU=";
  };

  nativeBuildInputs = [
    nodejs_26
    pnpm_12
    pnpmConfigHook
    node-gyp
    python3
    makeWrapper
    autoPatchelfHook
  ];

  buildInputs = [ stdenv.cc.cc.lib ];

  strictDeps = true;
  env = {
    pnpm_config_verify_deps_before_run = "false";
    T3CODE_WEB_SOURCEMAP = "false";
  };

  postPatch = # sh
    ''
      mkdir -p .generated/third-party-licenses/spdx/v3.28.0
      cp ${spdx-license-list-data.json}/json/details/*.json \
        .generated/third-party-licenses/spdx/v3.28.0/
    '';

  buildPhase = # sh
    ''
      runHook preBuild

      node scripts/update-release-package-versions.ts ${finalAttrs.version}
      node_modules/.bin/vp run --filter t3 build

      # Reuse the pinned workspace resolutions, but install only the dependencies
      # upstream leaves external to its server bundle.
      cp ${./stage-runtime.mjs} apps/server/stage-runtime.mjs
      node apps/server/stage-runtime.mjs "$TMPDIR/runtime"
      pnpm --dir "$TMPDIR/runtime" install --prod --offline --frozen-lockfile --ignore-scripts

      ptyDir=$(realpath "$TMPDIR/runtime/node_modules/node-pty")
      rm -rf "$ptyDir/prebuilds"
      node-gyp rebuild --directory="$ptyDir" --nodedir=${nodejs_26} \
        --jobs="''${NIX_BUILD_CORES:-1}"
      # Only the native addon is needed from node-gyp's build tree.
      cp "$ptyDir/build/Release/pty.node" "$TMPDIR/pty.node"
      rm -rf "$ptyDir/build"
      mkdir -p "$ptyDir/build/Release"
      mv "$TMPDIR/pty.node" "$ptyDir/build/Release/"
      # gyp also writes makefiles beside node-addon-api, outside build/. They
      # retain its build-time Node interpreter and are not runtime inputs.
      find "$TMPDIR/runtime/node_modules" -type f -name '*.mk' -delete

      runHook postBuild
    '';

  installPhase = # sh
    ''
      runHook preInstall

      mkdir -p "$out/lib/t3code" "$out/bin"
      cp -R apps/server/dist "$TMPDIR/runtime/"{node_modules,package.json} "$out/lib/t3code/"
      rm -f "$out/lib/t3code/node_modules/"{.modules.yaml,.pnpm-workspace-state-v1.json,.pnpm/lock.yaml}
      # ffi-rs incorrectly labels its musl binary as glibc-compatible. Neither it
      # nor its optional dependency links belong in this glibc runtime.
      find "$out/lib/t3code/node_modules" \( -name '*-linux-*-musl' -o -name '*-linux-*-musl@*' \) \
        -prune -exec rm -rf {} +
      find "$out/lib/t3code" -name '*.map' -type f -delete
      find "$out/lib/t3code" -type d -name .bin -prune -exec rm -rf {} +
      install -Dm644 LICENSE "$out/share/licenses/t3code/LICENSE"

      makeWrapper ${lib.getExe nodejs-slim_26} "$out/bin/t3" \
        --add-flags "$out/lib/t3code/dist/bin.mjs" \
        --prefix PATH : ${
          lib.makeBinPath [
            gitMinimal
            gh
          ]
        }

      runHook postInstall
    '';

  disallowedReferences = [
    nodejs_26
    node-gyp
    pnpm_12
    python3
  ];

  passthru = {
    tests.web = callPackage ./test.nix { t3code = finalAttrs.finalPackage; };
    updateScript = import ../lib/make-update-script.nix {
      inherit writeShellScript;
      pkgPath = ./.;
      name = "update-t3code";
    };
  };

  meta = {
    description = "Web interface and server for coding agents";
    homepage = "https://github.com/pingdotgg/t3code";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "t3";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
