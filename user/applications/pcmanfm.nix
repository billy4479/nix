{pkgs, ...}: {
  home.packages = with pkgs; [
    pcmanfm-qt
  ];

  programs.plasma = {
    enable = true;
    configFile."/pcmanfm-qt/default/settings.conf"."General" = {
      "Archiver" = "ark";
      "Terminal" = "kitty";
    };
  };
}
