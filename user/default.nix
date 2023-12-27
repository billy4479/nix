{ config, pkgs, user, nixpkgs, ... }:

{
  home.username = user.username;
  home.homeDirectory = "/home/${user.username}";

  # Enable unfree - yes, we have to do this here too
  nixpkgs.config.allowUnfree = true;

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
      options = {
        recolor = "true";
        guioptions = "none";
      };
    };
  };

  home.packages = with pkgs; [
    neovim
    fd
    ripgrep
    p7zip
    license-cli
    bat-extras.batman

    telegram-desktop
    spotify
    discord
  ];

  home.file = { };

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.home-manager.enable = true;
}
