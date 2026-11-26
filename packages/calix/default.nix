{
  lib,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  wrapGAppsHook4,
  gtk4,
  libadwaita,
  sqlite,
  xdg-utils,
  writeShellScript,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "calix";
  version = "0.10.0";

  src = fetchFromGitHub {
    owner = "ianswope";
    repo = "calix";
    tag = "v${finalAttrs.version}";
    hash = "sha256-3oi1cDOzRBpRcufaglHN7sNm2x0OXcsbspARSHEKuh4=";
  };

  # The lock file ships with the source, so it can never drift from the tag.
  cargoLock.lockFile = "${finalAttrs.src}/Cargo.lock";

  strictDeps = true;

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk4
    libadwaita
    # rusqlite asks for `bundled`, but that only reaches libsqlite3-sys through
    # an optional-dependency `?` edge, which does not fire on native targets.
    # The bindings come from the bundled copy while the link stays dynamic.
    sqlite
  ];

  # Google sign-in shells out to xdg-open to hand the consent screen to a
  # browser, so the wrapper has to carry it.
  preFixup = # sh
    ''
      gappsWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ xdg-utils ]})
    '';

  postInstall = # sh
    ''
      install -Dm644 dist/com.ianswope.Calix.desktop \
        "$out/share/applications/com.ianswope.Calix.desktop"
      install -Dm644 dist/com.ianswope.Calix.svg \
        "$out/share/icons/hicolor/scalable/apps/com.ianswope.Calix.svg"
      install -Dm644 dist/com.ianswope.Calix.metainfo.xml \
        "$out/share/metainfo/com.ianswope.Calix.metainfo.xml"
      install -Dm644 LICENSE "$out/share/licenses/calix/LICENSE"
    '';

  passthru.updateScript = import ../lib/make-update-script.nix {
    inherit writeShellScript;
    pkgPath = ./.;
    name = "update-calix";
  };

  meta = {
    description = "Native GTK4 calendar with Google, iCloud, and CalDAV sync";
    homepage = "https://github.com/ianswope/calix";
    changelog = "https://github.com/ianswope/calix/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "calix";
    platforms = [ "x86_64-linux" ];
  };
})
