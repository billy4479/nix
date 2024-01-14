{extraConfig, ...}:
assert !extraConfig.wayland; {
  # https://github.com/billy4479/dotfiles/blob/master/.config/picom/picom.conf
  services.picom = {
    enable = true;
    backend = "glx";

    fade = true;
    fadeDelta = 10;
    fadeSteps = [0.08 0.08];
    fadeExclude = [
      "class_g = 'Rofi'"
    ];

    vSync = true;

    settings = {
      corner-radius = 10;
      rounded-corners-exclude = [
        "window_type = 'dock'"
        "window_type = 'desktop'"
        "window_type = 'menu'"
        "class_g = 'Dunst'"
      ];

      inactive-opacity-override = false;
      detect-client-opacity = true;

      blur = {
        method = "dual_kawase";
        strength = 2;
        # kern = "3x3box";
        background-exclude = [
          "window_type = 'dock'"
          "window_type = 'desktop'"
          "_GTK_FRAME_EXTENTS@:c"
          "class_g = 'slop'"
        ];
      };

      xrender-sync-fence = true;
    };

    wintypes = {
      tooltip = {
        fade = false;
        shadow = false;
        opacity = 1;
        focus = true;
        full-shadow = false;
      };
      dock = {
        shadow = false;
        clip-shadow-above = true;
      };
      dnd = {shadow = false;};
      popup_menu = {
        opacity = 1;
        fade = false;
      };
      dropdown_menu = {opacity = 1;};
    };
  };
}
