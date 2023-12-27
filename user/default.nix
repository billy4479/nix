{ config, pkgs, user, ... }:

{
  home.username = user.username;
  home.homeDirectory = "/home/${user.username}";

  imports = [
    ./shell
    ./git.nix
    ./browser
    ./fonts
  ];

  home.stateVersion = "23.11";

  catppuccin = {
    flavour = "frappe";
    accent = "green";
  };

  programs = {
    zathura = {
      enable = true;
      catppuccin.enable = true;
    };
  };

  home.packages = with pkgs; [
    neovim
    fd
    ripgrep
    p7zip
    license-cli
  ];

  home.file = { };

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.home-manager.enable = true;
}
