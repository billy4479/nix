{ extraConfig, ... }:
let
  profileFile = "${extraConfig.user.username}.profile";
  profileName = "${extraConfig.user.username}'s profile";
in
{
  imports = [ ./catppuccin.nix ];

  programs.plasma = {
    enable = true;
    configFile."konsolerc"."Desktop Entry"."DefaultProfile".value = profileFile;
    dataFile."konsole/${profileFile}" = {
      "Appearance" = {
        "ColorScheme".value = "Catppuccin-Frappe";
        "Font".value = "${(import ../../../fonts/names.nix).mono},16,-1,5,53,0,0,0,0,0,Regular";
      };

      "General" = {
        "Name".value = profileName;
        "Parent".value = "FALLBACK/";
      };
    };
  };
}
