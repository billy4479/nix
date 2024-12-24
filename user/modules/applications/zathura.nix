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
      };
    };
  };
}
