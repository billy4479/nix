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
      ++ lib.optionals (extraConfig.hostname != "vps-proxy") [ scripts.notify-me ]
    else
      with scripts;
      [
        notify-me
        mpv-url
        open-document
        clip-copy
        clip-paste
        list-desktop-files
        flatten

        build-host-and-copy
      ]
      ++ lib.optionals (!extraConfig.wayland) [ dmenu-screenshot ];

  sops.secrets =
    lib.optionalAttrs (!extraConfig.isServer) { nix-signing-key = { }; }
    // lib.optionalAttrs (extraConfig.hostname != "vps-proxy") { smartd-telegram-env = { }; };
}
