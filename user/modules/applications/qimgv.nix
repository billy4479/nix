{ pkgs, extraPkgs, ... }:
{
  home.packages = [
    extraPkgs.my-packages.qimgv-qt6
  ];
}
