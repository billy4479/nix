{
  extraConfig,
  pkgs,
  config,
  lib,
  ...
}:
# We let KDE decide for KDE stuff
assert extraConfig.desktop != "kde";
let
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
in
{
  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "qt6ct";
  };

  home.packages =
    (with pkgs; [
      libsForQt5.qt5ct
      qt6Packages.qt6ct

      darkly
      darkly-qt5
    ])
    ++ [ papirus.package ];

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
    configFile =
      let
        fonts = import ./fonts/names.nix;
        conf = {
          "Appearance" = {
            "color_scheme_path".value =
              "${config.xdg.configHome}/qt5ct/colors/Catppuccin-${extraConfig.catppuccinColors.upper.flavor}.conf";
            "custom_palette".value = true;
            "icon_theme".value = papirus.name;
            "standard_dialogs".value = "xdgdesktopportal";
            "style".value = "Darkly";
          };

          "Fonts" = {
            "fixed".value = "\"${fonts.mono},12,-1,5,50,0,0,0,0,0,Regular\"";
            "general".value = "\"${fonts.sans},12,-1,5,50,0,0,0,0,0,Regular\"";
          };
        };
      in
      {
        "qt5ct/qt5ct.conf" = conf;
        "qt6ct/qt6ct.conf" = conf;
      };
  };
}
