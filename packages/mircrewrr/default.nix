{
  lib,
  fetchFromGitHub,
  stdenvNoCC,
  makeWrapper,
  python3,
  writeShellScript,
}:

let
  runtimeDependencies =
    ps: with ps; [
      beautifulsoup4
      flask
      lxml
      requests
      waitress
    ];

  pythonEnv = python3.withPackages runtimeDependencies;

  # The upstream tests need pytest, not part of the runtime environment.
  pythonTestEnv = python3.withPackages (ps: runtimeDependencies ps ++ [ ps.pytest ]);
in
stdenvNoCC.mkDerivation {
  pname = "mircrewrr";
  # Upstream tracks the app version by hand in src/admin/routes.py and publishes
  # no tags or releases, so the version follows the newest commit.
  version = "7.1.0-unstable-2026-10-26";

  src = fetchFromGitHub {
    owner = "easly1989";
    repo = "mircrewrr";
    rev = "e0f1f459571b432dce0297c5aefbe523e53a6278";
    hash = "sha256-igADrXuKA9wsJZ4o/qd5z8WyI2GnXXY7japC3ZBC8vs=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # Upstream ships no packaging metadata: sources are imported relative to src/
  # and the Docker image runs `python src/main.py`, so install the tree as-is
  # and wrap the interpreter with PYTHONPATH pointing at it.
  dontConfigure = true;
  dontBuild = true;

  installPhase = # sh
    ''
      runHook preInstall

      install -dm 755 $out/share/mircrewrr
      cp -r src $out/share/mircrewrr/src

      makeWrapper ${pythonEnv}/bin/python $out/bin/mircrewrr \
        --add-flags "$out/share/mircrewrr/src/main.py" \
        --set PYTHONPATH "$out/share/mircrewrr/src" \
        --set-default DATA_DIR /var/lib/mircrewrr

      runHook postInstall
    '';

  doCheck = true;
  nativeCheckInputs = [ pythonTestEnv ];
  checkPhase = # sh
    ''
      runHook preCheck
      PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PWD/src" python -m pytest tests
      runHook postCheck
    '';

  passthru = {
    inherit pythonEnv;
    updateScript = import ../lib/make-update-script.nix {
      inherit writeShellScript;
      pkgPath = ./.;
      name = "update-mircrewrr";
    };
  };

  meta = {
    description = "Torznab proxy for the MIRCrew indexer with a Cloudflare bypass and a web admin panel";
    homepage = "https://github.com/easly1989/mircrewrr";
    # The LICENSE file is GPLv3, despite the MIT badge in the README.
    license = lib.licenses.gpl3;
    mainProgram = "mircrewrr";
  };
}
