{
  config,
  pkgs,
  extraConfig,
  ...
}: {
  home.username = extraConfig.user.username;
  home.homeDirectory = "/home/${extraConfig.user.username}";

  # Enable unfree - yes, we have to do this here too
  nixpkgs.config.allowUnfree = true;

  imports =
    [
      ./applications
      ./cursor.nix
      ./fonts
      ./gtk.nix
      ./scripts
      ./services/syncthing.nix
      ./xdg-open.nix

      ./wallpapers.nix

      (import ./desktops extraConfig.desktop)
    ]
    ++ (
      if extraConfig.desktop != "kde"
      then [./qt.nix]
      else []
    );

  home.stateVersion = "23.11";

  catppuccin = {inherit (extraConfig.catppuccinColors) flavour accent;};

  home.packages = with pkgs; [
    # Shell utilities, not fundamental but still nice
    fd
    ripgrep
    p7zip
    zip
    license-cli
    bat-extras.batman
  ];

  xsession.numlock.enable = !extraConfig.wayland;

  home.file = {};

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.home-manager.enable = true;
}
