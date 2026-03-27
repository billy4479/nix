{ pkgs, ... }:
{
  # TODO: this file is here because I probably wanted to configure this...
  home.packages = with pkgs; [
    qimgv
  ];
}
