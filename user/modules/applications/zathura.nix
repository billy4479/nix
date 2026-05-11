{ lib, ... }:
{
  catppuccin.zathura.enable = true;
  programs = {
    zathura = {
      enable = true;
      options = {
        recolor = lib.mkDefault true;
        recolor-keephue = true;
        scroll-step = 60;
        font = (import ../fonts/names.nix).sans;
        guioptions = "none";
        database = "sqlite";

        default-bg = "rgba(48,52,70,0.85)";
        recolor-lightcolor = "rgba(0,0,0,0)";
      };
    };
  };
}
