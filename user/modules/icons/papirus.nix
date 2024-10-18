{ pkgs, catppuccinColors }:
{
  name = "Papirus-Dark";
  package = pkgs.catppuccin-papirus-folders.override {
    flavor = catppuccinColors.flavor;
    accent = catppuccinColors.accent;
  };
}
