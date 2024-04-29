{ pkgs
, extraConfig
, ...
}:
let
  cursor = import ./cursors {
    inherit pkgs;
    inherit (extraConfig) catppuccinColors;
  };
in
{
  home.pointerCursor = {
    inherit (cursor) name package;
    size = 10;
    gtk.enable = true;
    x11.enable = true; # We probably still want this because of xwayland
  };
}
