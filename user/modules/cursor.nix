{ pkgs, extraConfig, ... }:
let
  cursor = import ./cursors {
    inherit pkgs;
    inherit (extraConfig) catppuccinColors;
  };
in
{
  home.pointerCursor = {
    inherit (cursor) name package;
    size = 24;
    gtk.enable = true;
    x11.enable = true; # We probably still want this because of xwayland
  };

  programs.plasma.workspace.cursor = {
    theme = cursor.name;
    size = 24; # Idk how this number relates to the one before
  };
}
