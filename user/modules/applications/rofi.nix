{
  pkgs,
  extraConfig,
  catppuccinColors,
  ...
}:
{
  catppuccin.rofi.enable = true;
  programs.rofi = {
    enable = true;
    package = if extraConfig.wayland then pkgs.rofi-wayland else pkgs.rofi;
    font = "${(import ../fonts/names.nix).mono} 12";
    extraConfig = {
      modi = "drun,run";
      show-icons = true;
      icon-theme = (import ../icons/papirus.nix { inherit pkgs catppuccinColors; }).name;
    };
  };
}
