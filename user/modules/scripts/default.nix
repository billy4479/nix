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
  # Needed for generate-wg-config
  sops.secrets.serveronePublicIP = { };

  home.packages =
    with scripts;
    [
      mpv-url
      open-document
      generate-wg-config
    ]
    ++ lib.optionals (!extraConfig.wayland) [ dmenu-screenshot ];
}
