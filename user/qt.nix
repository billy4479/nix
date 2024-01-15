{
  extraConfig,
  pkgs,
  config,
  lib,
  ...
}:
# We let KDE decide for KDE stuff
assert extraConfig.desktop != "kde"; let
  srcs = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "qt5ct";
    rev = "89ee948e72386b816c7dad72099855fb0d46d41e";
    hash = "sha256-t/uyK0X7qt6qxrScmkTU2TvcVJH97hSQuF0yyvSO/qQ=";
  };

  papirus = import ./icons/papirus.nix {
    inherit pkgs;
    inherit (extraConfig) catppuccinColors;
  };

  # https://github.com/Stonks3141/ctp-nix/blob/main/modules/lib/default.nix#L49C1-L51C78
  mkUpper = str:
    with builtins;
      (lib.toUpper (substring 0 1 str)) + (substring 1 (stringLength str) str);
in {
  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "qt6ct";
  };

  home.packages = with pkgs;
    [qt5ct qt6ct lightly-qt]
    ++ [papirus.package];

  home.file."${config.xdg.configHome}/qt5ct/colors" = {
    source = "${srcs}/themes";
    recursive = true;
  };

  home.file."${config.xdg.configHome}/qt6ct/colors" = {
    source = "${srcs}/themes";
    recursive = true;
  };

  # Yes, it's not plasma but it's the same config format
  programs.plasma = {
    enable = true;
    configFile = let
      conf = {
        "Appearance" = {
          "color_scheme_path" = "${config.xdg.configHome}/qt5ct/colors/Catppuccin-${mkUpper extraConfig.catppuccinColors.flavour}.conf";
          "custom_palette" = true;
          "icon_theme" = papirus.name;
          "standard_dialogs" = "xdgdesktopportal";
          "style" = "Lightly";
        };

        "Fonts" = let
          fonts = import ./fonts/names.nix;
        in {
          "fixed" = "\"${fonts.mono},12,-1,5,50,0,0,0,0,0,Regular\"";
          "general" = "\"${fonts.sans},12,-1,5,50,0,0,0,0,0,Regular\"";
        };
      };
    in {
      "qt5ct/qt5ct.conf" = conf;
      "qt6ct/qt6ct.conf" = lib.recursiveUpdate conf {"Appearance"."style" = "Fusion";}; # Lightly is not available for qt6 yet
    };
  };
}
