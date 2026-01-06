{ pkgs, config, ... }:
{
  home.packages = [ pkgs.opencode ];
  home.file."${config.xdg.configHome}/opencode/opencode.json".source = ./config.json;
}
