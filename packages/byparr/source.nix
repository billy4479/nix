{ stdenvNoCC, version }:

let
  sourceTree = builtins.fetchTree {
    type = "github";
    owner = "ThePhaseless";
    repo = "Byparr";
    rev = "cb2a862386e92f141e8aa3b58f8532ef2fc36ed0";
    narHash = "sha256-coyi6e0dEy31gaiX8Mx+0pPZAI0eDNq1f+zrUqu3bVk=";
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
