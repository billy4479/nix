{extraConfig, ...}: {
  services.displayManager.autoLogin = {
    enable = true;
    user = extraConfig.user.username;
  };
}
