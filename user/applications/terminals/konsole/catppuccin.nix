{
  lib,
  pkgs,
  config,
  ...
}: let
  srcs = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "konsole";
    rev = "7d86b8a1e56e58f6b5649cdaac543a573ac194ca";
    hash = "sha256-EwSJMTxnaj2UlNJm1t6znnatfzgm1awIQQUF3VPfCTM=";
  };

  fileNames = builtins.filter (name: lib.strings.hasSuffix ".colorscheme" name) (builtins.attrNames (builtins.readDir srcs));
in {
  home.file = builtins.listToAttrs (map (file: {
      name = "${config.xdg.dataHome}/konsole/${file}";
      value.source = builtins.toPath "${srcs}/${file}";
    })
    fileNames);
}
