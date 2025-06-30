{
  extraConfig,
  pkgs,
  lib,
  ...
}:
{
  imports =
    (lib.trivial.throwIfNot (builtins.elem extraConfig.desktop [
      "kde"
      "qtile"
      "niri"
    ]) "The desktop \"${extraConfig.desktop}\" is not supported" [ ])
    ++ lib.optionals (extraConfig.desktop == "kde") [ ./kde ]
    ++ lib.optionals (extraConfig.desktop == "qtile") [ ./qtile ]
    ++ lib.optionals (extraConfig.desktop == "niri") [ ./niri ];

  home.packages =
    with pkgs;
    [ pavucontrol ] ++ (if (extraConfig.wayland) then [ wl-clipboard ] else [ xclip ]);
}
