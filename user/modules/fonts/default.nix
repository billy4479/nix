{ pkgs, extraPkgs, ... }:
{
  home.packages =
    [
      extraPkgs.my-packages.apple-fonts
    ]
    ++ (with pkgs; [
      corefonts
      ubuntu_font_family
      google-fonts
      nerd-fonts.fira-code
      nerd-fonts.bigblue-terminal
    ]);
}
