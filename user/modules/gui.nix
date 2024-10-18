{ extraConfig, ... }:
{
  xsession.numlock.enable = !extraConfig.wayland;

  catppuccin = {
    inherit (extraConfig.catppuccinColors) flavor accent;
  };
}
