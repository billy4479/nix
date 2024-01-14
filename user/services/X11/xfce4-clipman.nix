{pkgs, ...}: {
  home.packages = [pkgs.xfce.xfce4-clipman-plugin];

  systemd.user.services.xfce4-clipman = {
    Unit = {
      Description = "LxSession";
      After = ["graphical-session-pre.target"];
      PartOf = ["graphical-session.target"];
    };

    Install = {WantedBy = ["graphical-session.target"];};

    Service = {
      ExecStart = pkgs.xfce.xfce4-clipman-plugin;
      Restart = "always";
      RestartSec = 3;
    };
  };
}
