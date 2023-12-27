{ pkgs }:
pkgs.stdenv.mkDerivation rec {
  pname = "sf-pro-font";
  version = "0.0.1";

  src = pkgs.fetchFromGitHub {
    owner = "sahibjotsaggu";
    repo = "San-Francisco-Pro-Fonts";
    rev = "8bfea09aa6f1139479f80358b2e1e5c6dc991a58";
    hash = "sha256-mAXExj8n8gFHq19HfGy4UOJYKVGPYgarGd/04kUIqX4=";
  };

  buildInputs = [ ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/share/fonts/OTF/SF-Pro
    find -name \*.otf -exec mv {} $out/share/fonts/OTF/SF-Pro \;
  '';

  meta = with pkgs.lib; {
    description = "Apple San Francisco fonts";
    homepage = "https://developer.apple.com/fonts/";
    # license = pkgs.lib.licenses.unfree; # TODO: fix this
  };
}
