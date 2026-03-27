{ pkgs, ... }:
{
  home.packages = with pkgs; [
    apple-fonts
    google-sans

    corefonts
    ubuntu-sans
    google-fonts
    nerd-fonts.fira-code
    nerd-fonts.bigblue-terminal
  ];
}
