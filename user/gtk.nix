{
  pkgs,
  extraConfig,
  lib,
  ...
}: let
  # https://github.com/Stonks3141/ctp-nix/blob/main/modules/lib/default.nix#L49C1-L51C78
  mkUpper = str:
    with builtins;
      (lib.toUpper (substring 0 1 str)) + (substring 1 (stringLength str) str);
in {
  gtk = {
    enable = true;
    cursorTheme = import ./cursors pkgs;

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
          accents = [extraConfig.catppuccinColors.accent];
          variant = extraConfig.catppuccinColors.flavour;
        };

      name = "Catppuccin-${mkUpper extraConfig.catppuccinColors.flavour}-Standard-${mkUpper extraConfig.catppuccinColors.accent}-Dark";
    };
  };
}
