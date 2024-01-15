{
  pkgs,
  catppuccinColors,
}: {
  package = pkgs.catppuccin-cursors."${catppuccinColors.flavour}Dark";
  name = "Catppuccin-${catppuccinColors.upper.flavour}-Dark-Cursors";
}
