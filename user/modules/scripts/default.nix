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
    with scripts;
    [
      mpv-url
      open-document
      generate-wg-config
    ]
    ++ lib.optionals (!extraConfig.wayland) [ dmenu-screenshot ];
}
