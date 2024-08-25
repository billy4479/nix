{ pkgs, extraPkgs, ... }:
{
  home.packages = [
    extraPkgs.my-packages.apple-fonts
    (pkgs.nerdfonts.override { fonts = [ "FiraCode" ]; })
    pkgs.corefonts
    pkgs.ubuntu_font_family
  ];
}
