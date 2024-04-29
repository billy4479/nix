{ ... }: {
  xdg.enable = true;
  xdg.mimeApps = {
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
    };
  };
}
