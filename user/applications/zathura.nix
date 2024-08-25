{ lib, ... }:
{
  programs = {
    zathura = {
      enable = true;
      catppuccin.enable = true;
      options = {
        recolor = lib.mkDefault true;
        recolor-keephue = true;
        scroll-step = 60;
        font = "SF Pro Display";
        guioptions = "none";
      };
    };
  };
}
