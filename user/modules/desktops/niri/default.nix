{
  pkgs,
  extraConfig,
  config,
  ...
}:
# If bluetooth is enable we want to enable this.
# We already know that blueman will be enabled because of /system/modules/bluetooth.nix
assert extraConfig.wayland;
{
  home.file."${config.xdg.configHome}/niri/config.kdl".source = ./config.kdl;
  home.packages = [ pkgs.alacritty ];
}
