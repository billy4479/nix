{
  pkgs,
  config,
  lib,
  extraConfig,
  ...
}:
assert !extraConfig.wayland;
let
  wallpaperDir = "${config.xdg.userDirs.pictures}/wallpapers";
in
# bgForMonitor =
#   { monitorNum, bgPath }:
#   # ini
#   ''
#     [xin_${toString monitorNum}]
#     file=${bgPath}
#     mode=4
#     bgcolor=#000000
#
#   '';
{
  home.packages = [ pkgs.nitrogen ];

  # TODO: we should do something about `nitrogen.cfg` too
  home.file."${config.xdg.configHome}/nitrogen/bg-saved.cfg".text = # ini
    ''
      [xin_-1]
      file=${wallpaperDir}/catppuccin/math-huge.png
      mode=0
      bgcolor=#000000
    '';
  # bgForMonitor {
  #   monitorNum = 0;
  #   bgPath = "${wallpaperDir}/catppuccin/tent.png";
  # }
  # + bgForMonitor {
  #   monitorNum = 1;
  #   bgPath = "${wallpaperDir}/catppuccin/comet.png";
  # };

  systemd.user.services.nitrogen = {
    Unit = {
      Description = "Nitrogen";
      After = [ "graphical-session-pre.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = "${lib.getExe pkgs.nitrogen} --restore";
    };
  };
}
