{ pkgs, ... }:
{
  home.packages = with pkgs; [
    qimgv

    kdePackages.kimageformats
  ];
}
