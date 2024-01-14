{extraConfig, ...}: {
  services.xserver.displayManager.autoLogin = {
    enable = true;
    user = extraConfig.user.username;
  };
}
