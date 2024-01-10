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
    spotify
    discord
    joplin-desktop
    kate
    qbittorrent
    qalculate-gtk

    lightly-qt
  ];

  programs.mpv.enable = true; # TODO: there are some interesting configs here

  home.file = {};

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.home-manager.enable = true;
}
