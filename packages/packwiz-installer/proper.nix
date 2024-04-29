{ lib
, stdenvNoCC
, fetchFromGitHub
, # Build time
  zip
, unzip
, perl
, jdk8
, gradle_7
, makeWrapper
, # Run time
  jre
}:
let
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
    ./patches/0004-Add-resolve-task.patch
    ./patches/0005-Simplify-gradle-script.patch
    # ./patches/0006-Downgrade-okio-to-3.0.0.patch
  ];

  postPatch = ''
    substituteInPlace build.gradle.kts --replace \
     '###VERSION###' '${version}'
  '';

  gradleOptions = "--no-daemon --info --console=plain -Dorg.gradle.java.home=${jdk8}";
  exports = ''
    export HOME="$NIX_BUILD_TOP/home"
    export JAVA_TOOL_OPTIONS="-Duser.home='$HOME'"
    export GRADLE_USER_HOME="$HOME/.gradle"
  '';

  # The following code is taken from https://github.com/NixOS/nixpkgs/blob/master/pkgs/games/mindustry/default.nix
  deps = stdenvNoCC.mkDerivation {
    pname = "${pname}-deps";
    inherit version src postPatch patches;

    nativeBuildInputs = [ gradle_7 jdk8 perl zip ];
    buildPhase = ''
      ${exports}

      mkdir -p "$HOME"

      # Fetch the maven dependencies.
      gradle ${gradleOptions} resolveDependencies
    '';

    # Perl code mavenizes pathes (com.squareup.okio/okio/1.13.0/a9283170b7305c8d92d25aff02a6ab7e45d06cbe/okio-1.13.0.jar -> com/squareup/okio/okio/1.13.0/okio-1.13.0.jar)
    # See https://gist.github.com/billy4479/de7e233f5c0ed86ebcb3fe13dd5110c2 for more information
    installPhase = ''
      # find $GRADLE_USER_HOME/caches/modules-2 -type f -regex '.*\.\(jar\|pom\)' \
      #   | perl -pe 's#(.*/([^/]+)/([^/]+)/([^/]+)/[0-9a-f]{30,40}/([^/\s]+))$# ($x = $2) =~ tr|\.|/|; "install -Dm444 $1 \$out/maven/$x/$3/$4/$5" #e' \
      #   | sh

      mkdir -p $out
      ls -R $GRADLE_USER_HOME/caches > $out/ls.txt
      ls -R $GRADLE_USER_HOME/caches

      # mv $out/maven/org/jetbrains/kotlin/kotlin-gradle-plugin/1.7.10/kotlin-gradle-plugin-1.7.10{-gradle70,}.jar
      # mv $out/maven/org/jetbrains/kotlin/kotlin-gradle-plugin-api/1.7.10/kotlin-gradle-plugin-api-1.7.10{-gradle70,}.jar
      zip -r $out/caches.zip $GRADLE_USER_HOME/caches
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-meWTnjh+wyCZId7su7r53FFPgQU9RPLxJ3wVth+78Wg=";
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version src postPatch patches;

  nativeBuildInputs = [ deps gradle_7 jdk8 makeWrapper unzip ];
  buildInputs = [ jre ];

  dontStrip = true;

  buildPhase = ''
    ${exports}

    mkdir -p "$HOME" "$GRADLE_USER_HOME"

    # ln -s ${deps}/caches $GRADLE_USER_HOME/caches
    unzip -d . ${deps}/caches.zip

    # substituteInPlace build.gradle.kts --replace \
    #  'https://jitpack.io' 'file://${deps}/maven'
    # substituteInPlace build.gradle.kts --replace \
    #  'google()' ""
    # substituteInPlace build.gradle.kts --replace \
    #  'mavenCentral()' ""

    # FIXME: This is a hack around kotlin-gradle-plugin naming conventions being bounded to a specific version of gradle.
    #        Surely there is a better way to do this.
    #substituteInPlace build.gradle.kts --replace \
    # 'kotlin("jvm") version "1.7.10"' 'kotlin("jvm") version "1.7.10-gradle70"'

    # cat <<EOF > settings.gradle.kts
    # pluginManagement {
    #   repositories {
    #     maven(url = "${deps}/maven")
    #   }
    # }
    # rootProject.name = "${pname}"
    # EOF

    rm settings.gradle

    gradle ${gradleOptions} --offline build
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{bin,lib/${pname}}
    cp build/libs/${pname}.jar $out/lib/${pname}
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
