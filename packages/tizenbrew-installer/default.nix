{
  lib,
  stdenvNoCC,
  callPackage,
  fetchFromGitHub,
  fetchNpmDeps,
  makeWrapper,
  nodejs,
  npmHooks,
  writeShellScript,
}:

let
  inherit (npmHooks) npmConfigHook;

  version = "1.1.3";

  src = fetchFromGitHub {
    owner = "reisxd";
    repo = "TizenBrewInstaller";
    rev = "v${version}";
    hash = "sha256-4O0H/7VRyH4DMTKMq774k7MDD5VmhbVtsPEtqW2eROE=";
  };

  # The Preact UI, built with vite into the dist tree the service serves.
  ui = callPackage ./ui.nix { inherit src version; };

  # Production-only dependencies of the desktop service, installed from its
  # lockfile. The devDependencies are upstream's babel/ncc tooling to bundle
  # single-file binaries; the plain CommonJS sources run as-is, so we skip
  # that entirely. `tizen` is a GitHub tarball pinned by integrity in the
  # lockfile, which fetchNpmDeps verifies.
  serviceNodeModules = stdenvNoCC.mkDerivation {
    pname = "tizenbrew-installer-service-node-modules";
    inherit version src;
    sourceRoot = "${src.name}/client/services/tizenbrew-installer-service";

    npmDeps = fetchNpmDeps {
      name = "tizenbrew-installer-service-npm-deps-${version}";
      inherit src;
      sourceRoot = "${src.name}/client/services/tizenbrew-installer-service";
      hash = "sha256-HWxe9BdED0PNKUViQS4XEVAjdH1UsHuXcbwTYq/tzTQ=";
    };

    nativeBuildInputs = [
      nodejs
      npmConfigHook
    ];

    # npmConfigHook runs `npm ci --ignore-scripts` with these flags.
    npmInstallFlags = [ "--omit=dev" ];

    dontBuild = true;

    installPhase = # sh
      ''
        runHook preInstall
        cp -R node_modules $out
        runHook postInstall
      '';
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "tizenbrew-installer";
  inherit version src;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = # sh
    ''
      runHook preInstall

      root=$out/lib/tizenbrew-installer
      mkdir -p $out/bin $root/services/tizenbrew-installer-service $root/ui

      # Mirror the upstream client/ layout: the service statically serves the
      # folder two levels above its own directory and expects the UI at
      # ui/dist/index.html.
      cp -R ${ui} $root/ui/dist
      cp ${src}/client/services/tizenbrew-installer-service/index.js \
        $root/services/tizenbrew-installer-service/
      cp -R ${src}/client/services/tizenbrew-installer-service/utils \
        $root/services/tizenbrew-installer-service/
      cp -R ${serviceNodeModules} \
        $root/services/tizenbrew-installer-service/node_modules

      makeWrapper ${lib.getExe nodejs} $out/bin/tizenbrew-installer \
        --add-flags "$root/services/tizenbrew-installer-service/index.js"

      runHook postInstall
    '';

  passthru = {
    inherit ui serviceNodeModules;
    updateScript = import ../lib/make-update-script.nix {
      inherit writeShellScript;
      pkgPath = ./.;
      name = "update-tizenbrew-installer";
    };
  };

  meta = {
    description = "Install TizenBrew and other Tizen apps on Samsung TVs from the desktop";
    longDescription = ''
      Runs a local web app (http://localhost:8091/ui/dist/index.html) that
      talks to Samsung TVs over ADB to install TizenBrew and other Tizen
      packages, with certificate creation and resigning support for Tizen 7+
      TVs.
    '';
    homepage = "https://github.com/reisxd/TizenBrewInstaller";
    changelog = "https://github.com/reisxd/TizenBrewInstaller/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.gpl3Only;
    mainProgram = "tizenbrew-installer";
    inherit (nodejs.meta) platforms;
  };
})
