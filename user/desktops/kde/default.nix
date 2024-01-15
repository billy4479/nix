{pkgs, ...}: {
  home.packages = [pkgs.lightly-qt];

  programs.plasma = {
    enable = true;
    configFile = {
      "kwinrc" = {
        "NightColor" = {
          "Active" = true;
          "Mode" = "Constant";
          "NightTemperature" = 4900;
        };
        "Windows" = {
          "DelayFocusInterval" = 100;
          "FocusPolicy" = "FocusFollowsMouse";
        };
      };

      "kdeglobals"."KDE"."SingleClick" = false;
      "kcminputrc" = {
        # TODO: We don't want to hardcode the device name, see https://github.com/pjones/plasma-manager/issues/47
        "Libinput.10182.480.GXTP7863:00 27C6:01E0 Touchpad" = {
          "DisableWhileTyping" = false;
          "NaturalScroll" = true;
          "TapToClick" = true;
        };
      };
    };
  };
}
