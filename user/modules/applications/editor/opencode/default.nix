{ pkgs, config, ... }:
{
  home.packages = [ pkgs.opencode ];
  home.file."${config.xdg.configHome}/opencode" = {
    source = ./config;
    recursive = true;
  };
}
