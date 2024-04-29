{ pkgs, ... }: {
  home.packages = [ pkgs.lxqt.lxqt-policykit ];

  systemd.user.services.lxqt-policykit = {
    Unit = {
      Description = "lxqt-policykit";
      After = [ "graphical-session-pre.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Install = { WantedBy = [ "graphical-session.target" ]; };

    Service = {
      ExecStart = "${pkgs.lxqt.lxqt-policykit}/bin/lxqt-policykit-agent";
      Restart = "always";
      RestartSec = 3;
    };
  };
}
