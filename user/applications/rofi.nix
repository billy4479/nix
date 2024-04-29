{ pkgs
, catppuccinColors
, ...
}: {
  programs.rofi = {
    enable = true;
    font = "${(import ../fonts/names.nix).mono} 12";
    extraConfig = {
      modi = "drun,run";
      show-icons = true;
      icon-theme = (import ../icons/papirus.nix { inherit pkgs catppuccinColors; }).name;
    };
  };
}
