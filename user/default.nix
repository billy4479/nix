{
  config,
  pkgs,
  user,
  nixpkgs,
  ...
}: {
  home.username = user.username;
  home.homeDirectory = "/home/${user.username}";

  # Enable unfree - yes, we have to do this here too
  nixpkgs.config.allowUnfree = true;

  imports = [
    ./direnv.nix
    ./git.nix
    ./kde.nix
    ./spotify.nix
    ./xdg-open.nix
    ./zathura.nix
    ./shell
    ./browser
    ./fonts
    ./editor/nvim
    ./editor/vscodium
    ./terminal/konsole
  ];

  home.stateVersion = "23.11";

  catppuccin = {
    flavour = "frappe";
    accent = "green";
  };

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

    podman
    lightly-qt
    gcc
  ];

  xsession.numlock.enable = true;

  programs.mpv.enable = true; # TODO: there are some interesting configs here

  home.file = {};

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.home-manager.enable = true;
}
