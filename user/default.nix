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
    ./shell
    ./git.nix
    ./browser
    ./fonts
    ./vscodium
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
    joplin-desktop

    lightly-qt

    # Coding
    texliveMedium # This contains `latexmk`, the small version doesn't

    gcc
    llvmPackages_latest.clang-unwrapped
    cmake
    ninja

    cargo
    rustc
  ];

  xdg.mimeApps = {
    enable = true;
    associations.added = {
      "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
      "application/pdf" = "org.pwmt.zathura.desktop";
    };
    defaultApplications = {
      "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
      "application/pdf" = "org.pwmt.zathura.desktop";
    };
  };

  home.file = {};

  home.sessionVariables = {
    EDITOR = "nvim";
    CMAKE_GENERATOR = "Ninja";
  };

  programs.home-manager.enable = true;
}
