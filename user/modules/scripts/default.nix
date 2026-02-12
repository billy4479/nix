{
  pkgs,
  lib,
  config,
  extraConfig,
  ...
}@args:
let
  scripts = import ./packages.nix args;
in
{
  home.packages =
    if extraConfig.isServer then
      [
        scripts.activate-system
      ]
    else
      with scripts;
      [
        mpv-url
        open-document
        clip-copy
        clip-paste

        build-host-and-copy
      ]
      ++ lib.optionals (!extraConfig.wayland) [ dmenu-screenshot ];
}
