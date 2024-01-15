{pkgs, ...}: let
  cursor = import ./cursors pkgs;
in {
  home.pointerCursor = {
    inherit (cursor) name package;
    size = 32;
    gtk.enable = true;
    x11.enable = true; # We probably still want this because of xwayland
  };
}
