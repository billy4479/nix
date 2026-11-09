{ stdenvNoCC, version }:

let
  sourceTree = builtins.fetchTree {
    type = "github";
    owner = "ThePhaseless";
    repo = "Byparr";
    rev = "b041dd2998110fc61789ae65e2506bd5b79edba5";
    narHash = "sha256-YKymoOInKjpMx2L1y0ge87jUB0tcX3BnBJl81a0qf8k=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "byparr-source";
  inherit version;

  passthru.sourcePath = sourceTree.outPath;

  dontUnpack = true;
  # This output is source data, not installed executables.
  dontFixup = true;

  installPhase = # sh
    ''
      runHook preInstall
      cp -R "${sourceTree.outPath}/." "$out"
      runHook postInstall
    '';
}
