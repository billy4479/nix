{
  lib,
  stdenvNoCC,
  fetchurl,
  p7zip,
  fonts ? [ ],
}:
let
  urlsAndShas = {
    sf-pro = {
      url = "https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg";
      sha256 = "sha256-090HwtgILtK/KGoOzcwz1iAtoiShKAVjiNhUDQtO+gQ=";
    };
    sf-compact = {
      url = "https://devimages-cdn.apple.com/design/resources/download/SF-Compact.dmg";
      sha256 = "sha256-z70mts7oFaMTt4q7p6M7PzSw4auOEaiaJPItYqUpN0A=";
    };
    sf-mono = {
      url = "https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg";
      sha256 = "sha256-bUoLeOOqzQb5E/ZCzq0cfbSvNO1IhW1xcaLgtV2aeUU=";
    };
    ny = {
      url = "https://devimages-cdn.apple.com/design/resources/download/NY.dmg";
      sha256 = "sha256-HC7ttFJswPMm+Lfql49aQzdWR2osjFYHJTdgjtuI+PQ=";
    };
  };
  knownFonts = builtins.attrNames srcs;
  selectedFonts =
    if (fonts == [ ]) then
      knownFonts
    else
      let
        unknown = lib.subtractLists knownFonts fonts;
      in
      if (unknown != [ ]) then throw "Unknown font(s): ${lib.concatStringsSep " " unknown}" else fonts;
  srcs = builtins.mapAttrs (
    name: value: if builtins.elem name selectedFonts then fetchurl value else ""
  ) urlsAndShas;

  installFn =
    name: src:
    let
      folderName = builtins.replaceStrings [ " " ] [ "" ] name;
      outName = type: "$out/share/fonts/${type}/AppleFonts/${name}";
    in
    ''
      7z x ${src} -y
      cd ${folderName}
      7z x '${name}.pkg' -y
      7z x 'Payload~' -y
      mkdir -p "${outName "truetype"}" "${outName "opentype"}"
      find Library/Fonts -name \*.ttf -exec install -Dm644 {} "${outName "truetype"}" \;
      find Library/Fonts -name \*.otf -exec install -Dm644 {} "${outName "opentype"}" \;
      cd ..
    '';
in
stdenvNoCC.mkDerivation {
  pname = "apple-fonts";
  version = "1";

  nativeBuildInputs = [ p7zip ];

  sourceRoot = ".";

  dontUnpack = true;

  buildPhase = ''
    echo "Selected fonts are ${toString selectedFonts}"
  '';

  installPhase =
    (if builtins.elem "sf-pro" selectedFonts then installFn "SF Pro Fonts" srcs.sf-pro else "")
    + (
      if builtins.elem "sf-compact" selectedFonts then
        installFn "SF Compact Fonts" srcs.sf-compact
      else
        ""
    )
    + (if builtins.elem "sf-mono" selectedFonts then installFn "SF Mono Fonts" srcs.sf-mono else "")
    + (if builtins.elem "ny" selectedFonts then installFn "NY Fonts" srcs.ny else "");

  meta = {
    description = "Apple San Francisco and New York fonts";
    homepage = "https://developer.apple.com/fonts/";
    license = lib.licenses.unfree;
  };
}
