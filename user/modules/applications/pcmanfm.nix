{ pkgs, ... }:
{
  home.packages = [ pkgs.lxqt.pcmanfm-qt ];

  programs.plasma = {
    enable = true;
    configFile."pcmanfm-qt/default/settings.conf"."System" = {
      "Archiver".value = "ark";
      "Terminal".value = "kitty";
    };
  };

  xdg.mimeApps.defaultApplications."inode/directory" = [ "pcmanfm-qt.desktop" ];
}
