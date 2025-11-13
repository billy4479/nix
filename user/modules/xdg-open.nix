{ lib, ... }:
{
  xdg.enable = true;
  xdg.autostart.enable = true;
  xdg.configFile."mimeapps.list".force = true;
  xdg.mimeApps =
    let
      imgViewer = "qimgv.desktop";
      imgTypes = [
        "image/jpeg"
        "image/gif"
        "image/png"
        "image/bmp"
        "image/webp"
        "image/heif"
        "image/x-adobe-dng"
      ];
      imgTypesAttrSet = builtins.foldl' (acc: elem: acc // { "${elem}" = imgViewer; }) { } imgTypes;
    in
    {
      enable = true;
      associations.added = {
        "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
        "application/pdf" = "org.pwmt.zathura.desktop";
        "text/plain" = "org.kde.kate.desktop";
      };
      defaultApplications = {
        "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
        "application/pdf" = "org.pwmt.zathura.desktop";
        "text/plain" = "org.kde.kate.desktop";
      }
      // imgTypesAttrSet;
    };
}
