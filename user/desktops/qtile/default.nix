{
  lib,
  config,
  pkgs,
  wayland,
  bluetooth,
  ...
}:
# TODO: for now we use just the X11 version.
#       My config sucks and has to be rewritten
#       I also need to figure out what tools I need installed for Wayland to replace my X11 config.
assert !wayland; {
  home.file = {
    "${config.xdg.configHome}/qtile/config.py".source = ./config.py;
    "${config.xdg.configHome}/qtile/autostart.sh" = {
      # TODO: remove this, we should probably use systemd units
      source = ./autostart.sh;
      executable = true;
    };
  };

  imports =
    [
      ../../applications/rofi.nix
      ../../services/dunst.nix
      ../../services/gammastep.nix
      ../../services/kdeconnect.nix
      ../../services/nm-applet.nix
      ../../services/playerctld.nix
      ../../services/X11/nitrogen.nix
      ../../services/X11/picom.nix
    ]
    # If bluetooth is enable we want to enable this.
    # We already know that blueman will be enabled because of /system/modules/bluetooth.nix
    ++ lib.optional bluetooth ../../services/blueman-applet.nix;

  # TODO: this is stuff for which there is no home-manager module.
  #       If I find the time it would be nice to try writing one.
  home.packages = with pkgs; [
    lxsession
    xfce.xfce4-clipman-plugin
    pcmanfm-qt
  ];
}
