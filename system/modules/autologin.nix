{user, ...}: {
  services.xserver.displayManager.autoLogin = {
    enable = true;
    user = user.username;
  };
}
