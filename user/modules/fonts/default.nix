{ pkgs, extraPkgs, ... }:
{
  home.packages = [
    extraPkgs.my-packages.apple-fonts
    extraPkgs.my-packages.google-sans
  ]
  ++ (with pkgs; [
    corefonts
    ubuntu-sans
    google-fonts
    nerd-fonts.fira-code
    nerd-fonts.bigblue-terminal
  ]);
}
