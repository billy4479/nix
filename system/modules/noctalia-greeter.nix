{ extraConfig, lib, ... }:
{
  services.displayManager.noctalia-greeter = {
    enable = true;
    settings = {
      session.default = "niri";
      keyboard = {
        layout = "us,it";
        variant = "intl,";
        numlock = true;
      };
      idle.timeout = 300;

      # The greeter has its own compositor and does not read the Niri settings.
      output = lib.optionalAttrs (extraConfig.hostname == "computerone") {
        layout = "DP-1:${if extraConfig.rotateMonitor then "1080" else "1920"},0; DP-2:0,0";
        transforms = "DP-1:normal; DP-2:${if extraConfig.rotateMonitor then "90" else "normal"}";
        scales = "DP-1:1; DP-2:1";
        refresh_rate = "DP-1:170; DP-2:75";
      };
    };
  };
}
