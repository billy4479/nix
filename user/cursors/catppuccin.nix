{ pkgs
, catppuccinColors
,
}: {
  package = pkgs.catppuccin-cursors."${catppuccinColors.flavor}Dark";
  name = "catppuccin-${catppuccinColors.flavor}-dark-cursors";
}
