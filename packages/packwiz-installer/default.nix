{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  # Build time
  perl,
  jdk8,
  gradle_7,
  makeWrapper,
  # Run time
  jre,
}: let
  pname = "packwiz-installer";
  version = "0.5.13";

  src = fetchFromGitHub {
    owner = "packwiz";
    repo = "packwiz-installer";
    rev = "1ebb28c3ccea4bdd9df38615182826f564d7966e";
    hash = "sha256-RGp5WREpIfcztI3UNYkeflpFUoFNESbQe0Tx40+cRVU=";
  };

  patches = [
    ./patches/0001-Remove-git-version.patch
    ./patches/0002-Use-DevMain.patch
    ./patches/0003-Fix-command-line-arguments.patch
    # ./patches/0004-Add-resolve-task.patch
  ];

  postPatch = ''
    substituteInPlace build.gradle.kts --replace \
     '###VERSION###' '${version}'
  '';

  build = stdenvNoCC.mkDerivation {
    pname = "${pname}-build";
    inherit version src postPatch patches;

    nativeBuildInputs = [gradle_7 jdk8 perl];
    buildPhase = ''
      export HOME="$NIX_BUILD_TOP/home"
      mkdir -p "$HOME"
      export JAVA_TOOL_OPTIONS="-Duser.home='$HOME'"
      export GRADLE_USER_HOME="$HOME/.gradle"

      gradle --no-daemon --info --console=plain -Dorg.gradle.java.home=${jdk8} build
    '';

    installPhase = ''
      mkdir -p $out
      cp build/libs/packwiz-installer-${version}-all-repacked.jar $out/${pname}.jar
    '';

    dontStrip = true;

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-n9FjYiJXdKuWZPnUKUsisY6fnAdyV5xFdS8xLBqCESs=";
  };
in
  stdenvNoCC.mkDerivation {
    inherit pname version;
    nativeBuildInputs = [build makeWrapper];
    buildInputs = [jre];

    dontUnpack = true;
    dontBuild = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/{bin,lib/${pname}}
      cp ${build}/${pname}.jar $out/lib/${pname}
      makeWrapper ${jre}/bin/java $out/bin/${pname} \
        --add-flags "-jar $out/lib/${pname}/${pname}.jar"

      runHook postInstall
    '';

    meta = with lib; {
      homepage = "https://github.com/packwiz/packwiz-installer";
      description = "An installer for packwiz modpacks, with automatic auto-updating and optional mods";
      sourceProvenance = with sourceTypes; [
        fromSource
        binaryBytecode # deps are not built from source
      ];
      license = licenses.mit;
    };
  }
