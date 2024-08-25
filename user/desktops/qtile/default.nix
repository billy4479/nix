{
  lib,
  config,
  pkgs,
  extraConfig,
  ...
}:
# TODO: for now we use just the X11 version.
#       My config sucks and has to be rewritten
#       I also need to figure out what tools I need installed for Wayland to replace my X11 config.
#assert !extraConfig.wayland; 
{
  home.file = {
    "${config.xdg.configHome}/qtile/config.py".source = ./config.py;
  };

  imports =
    [
      ../../applications/rofi.nix
      ../../applications/pcmanfm.nix
      ../../services/dunst.nix
      ../../services/gammastep.nix
      ../../services/kdeconnect.nix
      ../../services/lxqt-policykit.nix
      ../../services/nm-applet.nix
      ../../services/playerctld.nix
      ../../services/udiskie.nix
    ]
    ++ (
      if !extraConfig.wayland then
        [
          ../../services/X11/autorandr.nix
          ../../services/X11/nitrogen.nix
          ../../services/X11/picom.nix
          ../../services/X11/volumeicon.nix
          ../../services/X11/xfce4-clipman.nix
        ]
      else
        [ ]
    )
    # If bluetooth is enable we want to enable this.
    # We already know that blueman will be enabled because of /system/modules/bluetooth.nix
    ++ lib.optional extraConfig.bluetooth ../../services/blueman-applet.nix;

  # TODO: this is stuff for which there is no home-manager module.
  #       If I find the time it would be nice to try writing one.
  home.packages =
    (with pkgs; [ pavucontrol ])
    ++ (
      if !extraConfig.wayland then
        (with pkgs; [
          # For screenshot script
          # TODO: adapt for wayland
          maim
          xclip
          xdotool
        ])
      else
        (with pkgs; [

        ])
    );

  # https://github.com/nix-community/home-manager/issues/2064#issuecomment-887300055
  systemd.user.targets.tray = {
    Unit = {
      Description = "Home Manager System Tray";
      Requires = [ "graphical-session-pre.target" ];
    };
  };
}
