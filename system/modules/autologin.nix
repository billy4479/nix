{
  config,
  extraConfig,
  ...
}:
if extraConfig.desktop == "niri" then
  {
    services.greetd.settings.initial_session = {
      user = extraConfig.user.username;
      command = "${config.programs.niri.package}/bin/niri-session";
    };
  }
else
  {
    services.displayManager.autoLogin = {
      enable = true;
      user = extraConfig.user.username;
    };
  }
