{
  config,
  pkgs,
  user,
  catppuccinColors,
  wayland,
  nixpkgs,
  desktop,
  ...
}: {
  home.username = user.username;
  home.homeDirectory = "/home/${user.username}";

  # Enable unfree - yes, we have to do this here too
  nixpkgs.config.allowUnfree = true;

  imports = [
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

    (import ./desktops desktop)
  ];

  home.stateVersion = "23.11";

  catppuccin = catppuccinColors;

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

    lightly-qt
    gcc
  ];

  xsession.numlock.enable = !wayland;

  programs.mpv.enable = true; # TODO: there are some interesting configs here

  home.file = {};

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.home-manager.enable = true;
}
