# https://gist.githubusercontent.com/robbins/dccf1238e971973a6a963b04c486c099/raw/08b77ef234a7fc44c34470de06f6d6ce25020255/apple-fonts.nix

{ lib, stdenvNoCC, fetchurl, p7zip, fonts ? [ ] }:

let
  urlsAndShas = {
    sf-pro = {
      url = "https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg";
      sha256 = "sha256-nkuHge3/Vy8lwYx9z+pvsQZfzrNIP4K0OutpPl4yXn0=";
    };
    sf-compact = {
      url = "https://devimages-cdn.apple.com/design/resources/download/SF-Compact.dmg";
      sha256 = "sha256-+Q4HInJBl3FLb29/x9utf7A55uh5r79eh/7hdQDdbSI=";
    };
    sf-mono = {
      url = "https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg";
      sha256 = "sha256-pqkYgJZttKKHqTYobBUjud0fW79dS5tdzYJ23we9TW4=";
    };
    ny = {
      url = "https://devimages-cdn.apple.com/design/resources/download/NY.dmg";
      sha256 = "sha256-XOiWc4c7Yah+mM7axk8g1gY12vXamQF78Keqd3/0/cE=";
    };
  };
  knownFonts = builtins.attrNames srcs;
  selectedFonts = if (fonts == [ ]) then knownFonts else
  let unknown = lib.subtractLists knownFonts fonts; in
  if (unknown != [ ]) then
    throw "Unknown font(s): ${lib.concatStringsSep " " unknown}"
  else fonts;
  srcs = builtins.mapAttrs
    (
      name:
      value:
      if builtins.elem name selectedFonts then
        fetchurl value
      else ""
    )
    urlsAndShas;

  installFn = name: src:
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
stdenvNoCC.mkDerivation rec {
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
    + (if builtins.elem "sf-compact" selectedFonts then installFn "SF Compact Fonts" srcs.sf-compact else "")
    + (if builtins.elem "sf-mono" selectedFonts then installFn "SF Mono Fonts" srcs.sf-mono else "")
    + (if builtins.elem "ny" selectedFonts then installFn "NY Fonts" srcs.ny else "");

  meta = {
    description = "Apple San Francisco, New York fonts";
    homepage = "https://developer.apple.com/fonts/";
    # license = lib.licenses.unfree; # FIXME
  };
}
