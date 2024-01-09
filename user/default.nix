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
    neovim
    fd
    ripgrep
    p7zip
    license-cli
    bat-extras.batman

    telegram-desktop
    spotify
    discord
    joplin-desktop

    lightly-qt
    kate

    qbittorrent

    # Coding
    # TODO: these should be in a dev shell
    texliveMedium # This contains `latexmk`, the small version doesn't

    gcc
    llvmPackages_latest.clang-unwrapped
    cmake
    ninja
  ];

  programs.plasma.enable = true;
  programs.mpv.enable = true; # TODO: there are some interesting configs here

  home.file = {};

  home.sessionVariables = {
    EDITOR = "nvim";
    CMAKE_GENERATOR = "Ninja";
  };

  programs.home-manager.enable = true;
}
