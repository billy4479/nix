{
  lib,
  config,
  pkgs,
  extraConfig,
  ...
}@args:
# TODO: for now we use just the X11 version.
#       My config sucks and has to be rewritten
#       I also need to figure out what tools I need installed for Wayland to replace my X11 config.
assert !extraConfig.wayland;
{
  home.file = {
    "${config.xdg.configHome}/qtile/config.py".text =
      let
        rofi = lib.getExe (if extraConfig.wayland then pkgs.rofi-wayland else pkgs.rofi);
        scripts = import ../../scripts/packages.nix args;
      in
      #python
      ''
        rofi = "${rofi}"
        open_document_script = "${lib.getExe scripts.open-document}"
        screenshot_script = "${lib.getExe scripts.dmenu-screenshot}"
        terminal = "${lib.getExe pkgs.wezterm}"

        ${builtins.readFile ./config.py}
      '';
  };

  home.activation = {
    # This is needed because otherwise qtile will still use the old, cached config.
    removePycache =
      lib.hm.dag.entryAfter [ "writeBoundary" ] # sh
        ''
          run rm -rf $VERBOSE_ARG ${config.xdg.configHome}/qtile/__pycache__
        '';
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

  # https://github.com/nix-community/home-manager/issues/2064#issuecomment-887300055
  systemd.user.targets.tray = {
    Unit = {
      Description = "Home Manager System Tray";
      Requires = [ "graphical-session-pre.target" ];
    };
  };
}
