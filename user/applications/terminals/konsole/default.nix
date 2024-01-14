{extraConfig, ...}: let
  profileFile = "${extraConfig.user.username}.profile";
  profileName = "${extraConfig.user.username}'s profile";
in {
  imports = [./catppuccin.nix];

  programs.plasma = {
    enable = true;
    configFile."konsolerc"."Desktop Entry"."DefaultProfile" = profileFile;
    dataFile."konsole/${profileFile}" = {
      "Appearance" = {
        "ColorScheme" = "Catppuccin-Frappe";
        "Font" = "${(import ../../../fonts/names.nix).mono},16,-1,5,53,0,0,0,0,0,Regular";
      };

      "General" = {
        "Name" = profileName;
        "Parent" = "FALLBACK/";
      };
    };
  };
}
