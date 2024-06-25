{ pkgs
, extraConfig
, ...
}: {
  gtk = {
    enable = true;
    cursorTheme = import ./cursors {
      inherit pkgs;
      inherit (extraConfig) catppuccinColors;
    };

    font = {
      name = (import ./fonts/names.nix).sans;
      size = 12;
    };

    iconTheme = import ./icons/papirus.nix {
      inherit pkgs;
      inherit (extraConfig) catppuccinColors;
    };
    gtk2.extraConfig = ''
      gtk-application-prefer-dark-theme=1
    '';
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };

    theme = {
      package = pkgs.gnome.gnome-themes-extra;
      name = "Adwaita";
    };
  };
}
