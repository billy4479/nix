{user, ...}: let
  profileFile = "${user.username}.profile";
  profileName = "${user.username}'s profile";
in {
  imports = [./catppuccin.nix];

  programs.plasma = {
    configFile."konsolerc"."Desktop Entry"."DefaultProfile" = profileFile;
    dataFile."konsole/${profileFile}" = {
      "Appearance" = {
        "ColorScheme" = "Catppuccin-Frappe";
        "Font" = "FiraCode Nerd Font Ret,16,-1,5,53,0,0,0,0,0,Regular";
      };

      "General" = {
        "Name" = profileName;
        "Parent" = "FALLBACK/";
      };
    };
  };
}
