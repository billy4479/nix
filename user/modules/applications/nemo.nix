{ pkgs, lib, ... }:
{
  # https://wiki.nixos.org/wiki/Nemo
  home.packages = [ pkgs.nemo ];

  xdg.desktopEntries.nemo = {
    name = "Nemo";
    exec = "${pkgs.nemo-with-extensions}/bin/nemo";
  };

  xdg.mimeApps = {
    defaultApplications = {
      "inode/directory" = [ "nemo.desktop" ];
      "application/x-gnome-saved-search" = [ "nemo.desktop" ];
    };
  };

  dconf.settings = with lib.hm.gvariant; {
    "org/cinnamon/desktop/applications/terminal" = {
      exec = "wezterm";
    };

    "org/nemo/preferences" = {
      inherit-show-thumbnails = false;
      quick-renames-with-pause-in-between = true;
      show-image-thumbnails = "local-only";
      thumbnail-limit = mkUint64 104857600;
    };
  };

}
