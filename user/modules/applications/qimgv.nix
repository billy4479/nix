{ pkgs, ... }:
{
  home.packages = with pkgs; [
    qimgv

    # Not sure I need both, just makeing sure
    libsForQt5.kimageformats
    kdePackages.kimageformats
  ];
}
