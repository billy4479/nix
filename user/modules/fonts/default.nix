{ pkgs, extraPkgs, ... }:
{
  home.packages =
    [
      extraPkgs.my-packages.apple-fonts
      (pkgs.nerdfonts.override { fonts = [ "FiraCode" ]; })
    ]
    ++ (with pkgs; [
      corefonts
      ubuntu_font_family
      google-fonts
    ]);
}
