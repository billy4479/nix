{ pkgs, ... }: {
  home.packages = [ pkgs.lightly-qt ];

  programs.plasma = {
    enable = true;
    configFile = {
      "kwinrc" = {
        "NightColor" = {
          "Active".value = true;
          "Mode".value = "Constant";
          "NightTemperature".value = 4900;
        };
        "Windows" = {
          "DelayFocusInterval".value = 100;
          "FocusPolicy".value = "FocusFollowsMouse";
        };
      };

      "kdeglobals"."KDE"."SingleClick".value = false;

      # TODO: We don't want to hardcode the device name, see https://github.com/pjones/plasma-manager/issues/47
      "kcminputrc" = {
        "Libinput/10182/480/GXTP7863:00 27C6:01E0 Touchpad" = {
          "DisableWhileTyping".value = false;
          "NaturalScroll".value = true;
          "TapToClick".value = true;
        };
      };
    };
  };
}
