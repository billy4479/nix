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

  programs.keepassxc = {
    enable = true;
    autostart = true;
  };

  home.packages =
    with pkgs;
    [
      fd
      ripgrep
      p7zip
      zip
      unzip
      unrar-free
      license-cli
      bat-extras.batman
      jq
      pv

      nixfmt
    ]
    ++ [
      pavucontrol
    ]
    ++ (if (extraConfig.wayland) then [ wl-clipboard ] else [ xclip ]);

  services.tailscale-systray.enable = true;
}
