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

    theme = {
      package =
        pkgs.catppuccin-gtk.override
          {
            accents = [ extraConfig.catppuccinColors.accent ];
            variant = extraConfig.catppuccinColors.flavor;
          };

      name = "Catppuccin-${extraConfig.catppuccinColors.upper.flavor}-Standard-${extraConfig.catppuccinColors.upper.accent}-Dark";
    };
  };
}
