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
      ./applications/browser
      ./applications/direnv.nix
      ./applications/editor/nvim
      ./applications/editor/vscodium
      ./applications/git.nix
      ./applications/shell
      ./applications/spotify.nix
      ./applications/terminals/kitty.nix
      ./applications/terminals/konsole
      ./applications/zathura.nix
      ./fonts
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

  catppuccin = extraConfig.catppuccinColors;

  home.packages = with pkgs; [
    # Shell utilities, not fundamental but still nice
    fd
    ripgrep
    p7zip
    license-cli
    bat-extras.batman

    # GUI stuff
    telegram-desktop
    discord
    joplin-desktop
    kate
    qbittorrent
    qalculate-gtk

    libreoffice-qt
    hunspell
    hunspellDicts.en_US
    hunspellDicts.it_IT

    kitty

    gcc
  ];

  xsession.numlock.enable = !extraConfig.wayland;

  programs.mpv.enable = true; # TODO: there are some interesting configs here

  home.file = {};

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.home-manager.enable = true;
}
