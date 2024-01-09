{...}: {
  programs.plasma = {
    enable = true;
    configFile = {
      "kdeglobals"."KDE"."SingleClick" = false;
    };
  };
}
