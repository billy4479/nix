{ config, pkgs, user, ... }:

{
  home.username = user.username;
  home.homeDirectory = "/home/${user.username}";

  imports = [
    ./shell
    ./git.nix
  ];

  home.stateVersion = "23.11";

  home.packages = with pkgs; [
    librewolf
    neovim

    # Fonts
    (nerdfonts.override {
      fonts = [ "FiraCode" ];
    })
  ];

  home.file = { };

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.home-manager.enable = true;
}
