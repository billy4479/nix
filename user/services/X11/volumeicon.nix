{ pkgs
, lib
, config
, extraConfig
, ...
}:
assert !extraConfig.wayland; {
  home.packages = [ pkgs.volumeicon ];

  home.file."${config.xdg.configHome}/volumeicon/volumeicon".text = ''
    [Alsa]
    card=default

    [Notification]
    show_notification=true
    notification_type=0

    [StatusIcon]
    stepsize=5
    onclick=${lib.getExe pkgs.pavucontrol}
    theme=Default
    use_panel_specific_icons=false
    lmb_slider=false
    mmb_mute=false
    use_horizontal_slider=false
    show_sound_level=false
    use_transparent_background=false

    [Hotkeys]
    up_enabled=false
    down_enabled=false
    mute_enabled=false
    up=XF86AudioRaiseVolume
    down=XF86AudioLowerVolume
    mute=XF86AudioMute
  '';

  systemd.user.services.volumeicon = {
    Unit = {
      Description = "Volume Icon";
      After = [ "graphical-session-pre.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Install = { WantedBy = [ "graphical-session.target" ]; };

    Service = {
      ExecStart = lib.getExe pkgs.volumeicon;
      Restart = "always";
      RestartSec = 3;
    };
  };
}
