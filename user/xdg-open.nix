{...}: {
  xdg.mimeApps = {
    enable = true;
    associations.added = {
      "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
      "application/pdf" = "org.pwmt.zathura.desktop";
    };
    defaultApplications = {
      "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
      "application/pdf" = "org.pwmt.zathura.desktop";
    };
  };
}
