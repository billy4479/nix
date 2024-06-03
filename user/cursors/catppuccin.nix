{ pkgs
, catppuccinColors
,
}: {
  package = pkgs.catppuccin-cursors."${catppuccinColors.flavor}Dark";
  name = "Catppuccin-${catppuccinColors.upper.flavor}-Dark-Cursors";
}
