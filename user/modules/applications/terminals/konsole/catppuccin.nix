{
  lib,
  pkgs,
  config,
  ...
}:
let
  srcs = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "konsole";
    rev = "3b64040e3f4ae5afb2347e7be8a38bc3cd8c73a8";
    hash = "sha256-d5+ygDrNl2qBxZ5Cn4U7d836+ZHz77m6/yxTIANd9BU=";
  };

  fileNames = builtins.filter (name: lib.strings.hasSuffix ".colorscheme" name) (
    builtins.attrNames (builtins.readDir "${srcs}/themes")
  );
in
{
  home.file = builtins.listToAttrs (
    map (file: {
      name = "${config.xdg.dataHome}/konsole/${file}";
      value.source = builtins.toPath "${srcs}/themes/${file}";
    }) fileNames
  );
}
