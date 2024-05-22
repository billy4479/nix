{ ... }: {
  xdg.enable = true;
  xdg.mimeApps =
    let
      imgViewer = "qimgv.desktop";
    in
    {
      enable = true;
      associations.added = {
        "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
        "application/pdf" = "org.pwmt.zathura.desktop";
        "text/plain" = "org.kde.kate.desktop";
        "inode/directory" = "pcmanfm-qt.desktop";
      };
      defaultApplications = {
        "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
        "application/pdf" = "org.pwmt.zathura.desktop";
        "text/plain" = "org.kde.kate.desktop";
        "inode/directory" = "pcmanfm-qt.desktop";
        "image/jpeg" = imgViewer;
        "image/gif" = imgViewer;
        "image/png" = imgViewer;
        "image/bmp" = imgViewer;
        "image/webp" = imgViewer;
      };
    };
}
