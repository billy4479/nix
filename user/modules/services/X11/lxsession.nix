{ pkgs, extraConfig, ... }:
assert !extraConfig.wayland;
{
  home.packages = [ pkgs.lxsession ];

  systemd.user.services.lxsession = {
    Unit = {
      Description = "LxSession";
      After = [ "graphical-session-pre.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.lxsession}/bin/lxsession";
      Restart = "always";
      RestartSec = 3;
    };
  };
}
