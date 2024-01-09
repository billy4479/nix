{...}: {
  programs.plasma = {
    enable = true;
    configFile = {
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
