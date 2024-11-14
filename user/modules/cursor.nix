{ pkgs, extraConfig, ... }:
let
  cursor = import ./cursors {
    inherit pkgs;
    inherit (extraConfig) catppuccinColors;
  };
  size = 20;
in
{
  home.pointerCursor = {
    inherit (cursor) name package;
    inherit size;
    gtk.enable = true;
    x11.enable = true; # We probably still want this because of xwayland
  };

  programs.plasma.workspace.cursor = {
    theme = cursor.name;
    inherit size;
  };
}
